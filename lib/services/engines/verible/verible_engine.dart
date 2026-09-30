// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/verible_rule_profile.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/bundled_binary_resolver.dart';
import 'package:lintcrux/services/engines/process_runner.dart';
import 'package:lintcrux/services/engines/verible/builtin_rule_profiles.dart';
import 'package:lintcrux/services/engines/verible/verible_parser.dart';

/// How many output lines an [EngineRunFailedException] carries into the
/// diagnostics panel. Enough to show `ERROR: unknown command line flag …`
/// plus the usage banner's first lines; bounded so a runaway engine can't
/// push a megabyte into a snackbar.
const int _kOutputExcerptLines = 10;

/// One completed `verible-verilog-lint` invocation.
class _VeribleAttempt {
  const _VeribleAttempt({
    required this.executable,
    required this.textMode,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final String executable;
  final bool textMode;
  final int exitCode;
  final List<String> stdout;
  final List<String> stderr;

  /// Whether the binary refused one of the flags we passed. Upstream
  /// Abseil flag parsing answers `ERROR: unknown command line flag
  /// 'lint_output'` (some builds capitalize differently or say "Unknown"),
  /// then prints usage and exits non-zero without linting anything.
  bool get rejectedAFlag {
    for (final line in <String>[...stderr, ...stdout]) {
      final lower = line.toLowerCase();
      if (lower.contains('unknown command line flag') ||
          lower.contains('unrecognized command line flag') ||
          (lower.contains('unknown flag') && lower.contains('error'))) {
        return true;
      }
    }
    return false;
  }
}

/// LintCrux [LintEngine] wrapper around `verible-verilog-lint`.
///
/// The engine asks for a structured `--lint_output=jsonline` surface
/// first so the parser does not have to disambiguate the human-readable
/// text output. **No upstream `verible-verilog-lint` release accepts that
/// flag** — a stock binary answers `ERROR: unknown command line flag
/// 'lint_output'` and exits non-zero having linted nothing. The engine
/// detects the rejection in either output stream and **retries in text
/// mode automatically**; `textModeFallback: true` in
/// [LintRunRequest.options] skips the wasted first attempt but is no
/// longer required for correctness.
///
/// Both streams are parsed on every attempt: upstream writes text-mode
/// diagnostics to **stderr**, and structured output would arrive on
/// stdout.
///
/// A non-zero exit is not by itself a failure — `verible-verilog-lint`
/// exits 1 precisely *because* it found violations. A non-zero exit that
/// produces no parseable violation is, and raises
/// [EngineRunFailedException] rather than reporting a clean run.
///
/// `.rules.verible_lint`: when [LintRunRequest.options] contains
/// `rulesConfigSearch: true` *or* a `.rules.verible_lint` file exists
/// in the project root ([LintRunRequest.projectRoot]), the engine adds
/// `--rules_config_search` so Verible discovers and applies the
/// project's per-directory config.
///
/// Rule profiles: [LintRunRequest.options] may carry
/// `ruleProfile: '<id>'` (see [kVeribleRuleProfileOptionKey]) naming
/// one of the curated [builtinVeribleRuleProfiles] — e.g. `'lowrisc'`
/// for the lowRISC / OpenTitan Verilog style guide. The profile
/// contributes `--ruleset=<base> --rules=<specs>` *before*
/// [EngineBinaryConfig.extraArgs], so a power user's own flags still
/// win. An id no profile claims raises [EngineRunFailedException]
/// rather than quietly linting against Verible's defaults — a run under
/// a rule set nobody chose is the same false-confidence failure as a
/// silent false-clean.
class VeribleEngine implements LintEngine {
  /// Creates a [VeribleEngine].
  VeribleEngine({
    this.runner = const SystemProcessRunner(),
    this.projectRoot = '',
    this.bundledBinaryResolver = const BundledBinaryResolver(),
  });

  /// The process runner. Tests inject a fake; production uses
  /// [SystemProcessRunner].
  final ProcessRunner runner;

  /// Fallback project root, used to resolve relative paths in engine
  /// output and to look for `.rules.verible_lint` when a request carries
  /// no [LintRunRequest.projectRoot].
  final String projectRoot;

  /// Bundled-binary resolver, consulted when [EngineBinaryConfig.source]
  /// is [EngineBinarySource.bundled].
  final BundledBinaryResolver bundledBinaryResolver;

  LintProcess? _process;

  @override
  String get id => 'verible';

  @override
  String get displayName => 'Verible';

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {
      HdlLanguage.verilog,
      HdlLanguage.systemVerilog,
    },
    emitsStructuredOutput: true,
    supportsConfigFile: true,
    // Verible's `verible-verilog-lint <files>` is inherently
    // per-file; the engine has no project-level analysis. Scoping
    // the file list to just the changed file(s) is the natural
    // incremental path.
    supportsIncrementalPerFile: true,
  );

  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) {
    final scoped = changedFiles
        .where(request.sourceFiles.contains)
        .toList(growable: false);
    if (scoped.isEmpty) return const Stream<Violation>.empty();
    return run(request.copyWith(sourceFiles: scoped));
  }

  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async {
    final exe = _resolveExecutable(config);
    try {
      final proc = await runner.start(exe, const ['--version']);
      final output = await collectProcessOutput(
        proc,
        engineId: id,
        executable: exe,
      );
      if (output.exitCode != 0) return null;
      final candidate = <String>[
        ...output.stdout,
        ...output.stderr,
      ].firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
      return candidate.isEmpty ? null : candidate.trim();
    } on ProcessException {
      return null;
    } on EngineNotAvailableException {
      return null;
    } on EngineRunFailedException {
      return null;
    }
  }

  @override
  Stream<Violation> run(LintRunRequest request) async* {
    final root = projectRoot.isNotEmpty
        ? projectRoot
        : (request.sourceFiles.isNotEmpty
              ? _dirname(request.sourceFiles.first)
              : '');
    final parser = VeribleParser(rootPath: root);
    final forcedTextMode = request.options['textModeFallback'] == true;

    var attempt = await _invoke(request, root, textMode: forcedTextMode);

    // Automatic text-mode fallback. `--lint_output=jsonline` is not a flag
    // any upstream `verible-verilog-lint` release accepts — a stock binary
    // answers with `ERROR: unknown command line flag 'lint_output'` and
    // exits non-zero having linted nothing. That used to produce a
    // *silent false-clean*: zero parseable lines, no error, "Completed
    // with 0 violations" on a file with thousands of findings. Retrying
    // without the flag is now automatic; `textModeFallback` in
    // `LintRunRequest.options` remains only as a way to skip the wasted
    // first attempt.
    if (!forcedTextMode && attempt.rejectedAFlag) {
      attempt = await _invoke(request, root, textMode: true);
    }

    // Upstream writes text-mode diagnostics to stderr; the (hypothetical)
    // structured mode writes to stdout. Parse both so neither stream can
    // strand findings.
    final outputLines = <String>[...attempt.stdout, ...attempt.stderr];
    final violations = attempt.textMode
        ? parser.parseText(outputLines)
        : parser.parseJsonLines(outputLines);

    // The false-clean contract. `verible-verilog-lint` exits non-zero when
    // it FINDS violations, so a non-zero exit is not itself an error — but
    // a non-zero exit that yields no violations means the invocation failed
    // (rejected flag, unreadable source, bad `--rules` spec) and must never
    // be reported as a completed clean run.
    if (attempt.exitCode != 0 && violations.isEmpty) {
      throw EngineRunFailedException(
        engineId: id,
        exitCode: attempt.exitCode,
        reason: outputLines.where((l) => l.trim().isNotEmpty).isEmpty
            ? 'exited ${attempt.exitCode} with no output'
            : 'exited ${attempt.exitCode} without producing a parseable '
                  'violation',
        outputExcerpt: outputLines
            .where((l) => l.trim().isNotEmpty)
            .take(_kOutputExcerptLines)
            .toList(growable: false),
        resolvedPath: attempt.executable,
      );
    }

    for (final v in violations) {
      yield v;
    }
  }

  /// One `verible-verilog-lint` invocation: spawns the process, drains
  /// BOTH streams to completion, and reports the captured output.
  Future<_VeribleAttempt> _invoke(
    LintRunRequest request,
    String root, {
    required bool textMode,
  }) async {
    final exe = _resolveExecutable(request.binary);
    final args = _buildArgs(request, textMode: textMode);

    final LintProcess proc;
    try {
      proc = await runner.start(exe, args, workingDirectory: root);
    } on ProcessException catch (e) {
      throw EngineNotAvailableException(
        engineId: id,
        reason: 'could not start "$exe": ${e.message}',
        resolvedPath: exe,
        cause: e,
      );
    }
    _process = proc;

    // Read to end-of-file, not to the exit: a stock binary's whole answer to
    // `--lint_output` is one rejection line, which routinely lands after the
    // exit code. Dropping it skipped the text-mode retry and failed the run.
    final CapturedProcessOutput output;
    try {
      output = await collectProcessOutput(
        proc,
        engineId: id,
        executable: exe,
      );
    } finally {
      _process = null;
    }
    return _VeribleAttempt(
      executable: exe,
      textMode: textMode,
      exitCode: output.exitCode,
      stdout: output.stdout,
      stderr: output.stderr,
    );
  }

  @override
  void cancel() {
    final p = _process;
    if (p != null) {
      p.kill();
    }
  }

  String _resolveExecutable(EngineBinaryConfig config) {
    switch (config.source) {
      case EngineBinarySource.custom:
        return config.path ?? 'verible-verilog-lint';
      case EngineBinarySource.bundled:
        // Resolver keys by engine id; the manifest writes the binary as
        // `verible` (not `verible-verilog-lint`) so first-run on a
        // bundled distribution doesn't repeat the long suffix.
        return bundledBinaryResolver.resolve(id) ?? 'verible-verilog-lint';
      case EngineBinarySource.system:
        return 'verible-verilog-lint';
    }
  }

  /// Whether [root] (the request's project root, else the constructor's
  /// [projectRoot]) contains a `.rules.verible_lint` config file. Public
  /// for tests; production callers shouldn't need this.
  bool projectHasConfigFile([String? root]) {
    final dir = (root != null && root.isNotEmpty) ? root : projectRoot;
    if (dir.isEmpty) return false;
    final path = dir.endsWith('/')
        ? '$dir.rules.verible_lint'
        : '$dir/.rules.verible_lint';
    return File(path).existsSync();
  }

  List<String> _buildArgs(
    LintRunRequest request, {
    required bool textMode,
  }) {
    final args = <String>[];
    if (!textMode) {
      args.add('--lint_output=jsonline');
    }
    final wantsConfigSearch =
        request.options['rulesConfigSearch'] == true ||
        projectHasConfigFile(request.projectRoot);
    if (wantsConfigSearch) {
      args.add('--rules_config_search');
    }
    final profile = _resolveRuleProfile(request);
    if (profile != null) {
      args.addAll(profile.toVeribleArgs());
    }
    args
      ..addAll(request.binary.extraArgs)
      ..addAll(request.sourceFiles);
    return args;
  }

  /// Resolves the `ruleProfile` option to a curated profile.
  ///
  /// Returns `null` when the option is absent or empty (run with
  /// Verible's own defaults). A non-empty value that names no shipped
  /// profile raises [EngineRunFailedException]: a typo in
  /// `project.lintcrux` must fail the engine loudly, not silently
  /// downgrade the project to an unintended rule set.
  VeribleRuleProfile? _resolveRuleProfile(LintRunRequest request) {
    final raw = request.options[kVeribleRuleProfileOptionKey];
    if (raw == null) return null;
    if (raw is! String || raw.isEmpty) {
      throw EngineRunFailedException(
        engineId: id,
        exitCode: -1,
        reason:
            '"$kVeribleRuleProfileOptionKey" must be a non-empty rule-profile '
            'id string; got ${raw.runtimeType}',
      );
    }
    final profile = veribleRuleProfileById(raw);
    if (profile == null) {
      final known = builtinVeribleRuleProfiles().map((p) => p.id).join(', ');
      throw EngineRunFailedException(
        engineId: id,
        exitCode: -1,
        reason: 'unknown Verible rule profile "$raw" (known: $known)',
      );
    }
    return profile;
  }

  String _dirname(String filePath) {
    final i = filePath.lastIndexOf('/');
    if (i < 0) return '.';
    return filePath.substring(0, i);
  }
}
