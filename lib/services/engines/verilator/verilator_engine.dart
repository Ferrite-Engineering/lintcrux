// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/bundled_binary_resolver.dart';
import 'package:lintcrux/services/engines/process_runner.dart';
import 'package:lintcrux/services/engines/verilator/verilator_parser.dart';
import 'package:lintcrux/services/engines/verilator/verilator_sarif_parser.dart';
import 'package:path/path.dart' as p;

/// Where [VerilatorEngine] reads its findings from.
enum VerilatorOutputMode {
  /// Parse Verilator's stderr transcript. One process per run.
  text,

  /// Read Verilator's SARIF output when the binary's version writes it
  /// (5.038 and later), the stderr transcript otherwise or whenever the
  /// SARIF file cannot be used.
  auto,
}

/// How many lines of the captured stderr transcript to attach to an
/// [EngineRunFailedException] so the diagnostics panel can show *why*
/// the run failed (e.g. `%Error: Cannot find file containing module`).
const int _kOutputExcerptLines = 10;

/// LintCrux [LintEngine] wrapper around Verilator's `--lint-only` mode.
///
/// The engine invokes the configured `verilator` binary with
/// `--lint-only`, project include / define flags, and the source file
/// list, then streams the parsed [Violation]s back as Verilator's
/// stderr arrives. Cancellation kills the subprocess.
///
/// Warning-flag configuration lives in `LintRunRequest.options` under the
/// `warnFlags` key — a `List<String>` of Verilator warning selectors
/// without the leading `-W` (e.g. `['all', 'no-DECLFILENAME']`). The
/// engine prepends `-W` and passes them through, exactly as [GhdlEngine]
/// does for `--warn-*`. The `.lintcrux` per-engine options bag persists
/// the choice per project.
///
/// Two more project-scoped option keys, both `List<String>`, both fed
/// by the FuseSoC EDAM importer and both usable by hand-edited
/// projects too: `extraOptions` — raw flags appended verbatim (e.g.
/// `-G` parameter overrides) — and `waiverFiles` — Verilator `.vlt`
/// waiver/config files, appended after the flags and **before** the
/// sources they waive, mirroring Edalize's argument ordering. `.vlt`
/// files ride this channel rather than `sourceFiles` because every
/// other engine would reject them as HDL.
///
/// [defaultWarnFlags] is `['all']` and that default is load-bearing:
/// Verilator's most useful lint checks — UNUSEDSIGNAL, UNDRIVEN,
/// DECLFILENAME, PINMISSING, VARHIDDEN, UNUSEDPARAM, UNUSEDGENVAR,
/// IMPORTSTAR, SYNCASYNCNET, DEFPARAM, INCABSPATH, PINCONNECTEMPTY — are
/// **off** unless `-Wall` is passed. An earlier revision of this engine
/// passed no warning flags at all, so none of them could ever fire and a
/// project whose only defects were in that set linted green. Do not
/// "simplify" the flag away.
///
/// The binary resolves from `PATH` (system source); bundled per-platform
/// binaries do not ship yet, and custom paths come from the Settings → Engines
/// UI. Missing-binary cases surface as [EngineNotAvailableException] either on
/// the returned stream or as a `null` from [detectVersion].
class VerilatorEngine implements LintEngine {
  /// Creates a [VerilatorEngine].
  VerilatorEngine({
    this.runner = const SystemProcessRunner(),
    this.projectRoot = '',
    this.bundledBinaryResolver = const BundledBinaryResolver(),
    this.outputMode = VerilatorOutputMode.text,
  });

  /// Where findings are read from. [VerilatorOutputMode.text] (the default)
  /// parses stderr and spawns exactly one process per run;
  /// [VerilatorOutputMode.auto], which the production registry selects,
  /// reads Verilator's SARIF output when its version is
  /// [minSarifMajor].[minSarifMinor] or later and falls back to stderr
  /// otherwise.
  final VerilatorOutputMode outputMode;

  /// First Verilator release with `--diagnostics-sarif-output`: 5.038.
  static const int minSarifMajor = 5;

  /// See [minSarifMajor].
  static const int minSarifMinor = 38;

  /// Whether a `verilator --version` line names a release that writes SARIF
  /// ([minSarifMajor].[minSarifMinor] or later). `null` and a line that is
  /// not a Verilator version are `false`, so an unknown binary is read the
  /// way every Verilator was read before SARIF.
  static bool versionWritesSarif(String? versionLine) {
    if (versionLine == null) return false;
    final m = RegExp(r'Verilator\s+(\d+)\.(\d+)').firstMatch(versionLine);
    if (m == null) return false;
    final major = int.parse(m.group(1)!);
    final minor = int.parse(m.group(2)!);
    return major > minSarifMajor ||
        (major == minSarifMajor && minor >= minSarifMinor);
  }

  /// `--version` result per executable, for this engine's lifetime.
  final Map<String, bool> _sarifSupport = <String, bool>{};

  /// The process runner. Tests inject a fake; production uses
  /// [SystemProcessRunner].
  final ProcessRunner runner;

  /// Absolute project root used to resolve relative paths reported in
  /// Verilator output. Empty (the default) falls back to the directory
  /// of the first source file in the request.
  final String projectRoot;

  /// Bundled-binary resolver, consulted when [EngineBinaryConfig.source]
  /// is [EngineBinarySource.bundled]. Tests inject one with a
  /// [BundledBinaryResolver.overrideRoot] pointing at a temp directory.
  final BundledBinaryResolver bundledBinaryResolver;

  /// The default `-W*` selector set used when the per-project options bag
  /// does not declare an explicit `warnFlags` list.
  ///
  /// `all` turns on Verilator's opt-in lint set. Without it the engine
  /// reports only the always-on codes (WIDTH*, CASE*, LATCH, …) and every
  /// housekeeping check a linting product is bought for stays silent.
  static const List<String> defaultWarnFlags = <String>['all'];

  LintProcess? _process;

  @override
  String get id => 'verilator';

  @override
  String get displayName => 'Verilator';

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.verilog, HdlLanguage.systemVerilog},
    // Verilator's `--lint-only <files>` re-runs the parse + check
    // pipeline over a caller-supplied file list. Incremental
    // re-runs scope that list to just the changed file(s); the
    // includes and defines still apply so the changed file
    // elaborates against the same project headers.
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
    if (scoped.isEmpty) {
      // Nothing in the request matched the watcher's set — emit no
      // violations rather than falling through to a full whole-project
      // run that the orchestrator already filtered out.
      return const Stream<Violation>.empty();
    }
    return run(request.copyWith(sourceFiles: scoped));
  }

  @override
  Future<String?> detectVersion(EngineBinaryConfig config) =>
      _probeVersion(_resolveExecutable(config));

  Future<String?> _probeVersion(String exe) async {
    try {
      final proc = await runner.start(exe, const ['--version']);
      final output = await collectProcessOutput(
        proc,
        engineId: id,
        executable: exe,
      );
      if (output.exitCode != 0) return null;
      // `verilator --version` prints a single line like
      // `Verilator 5.022 2024-07-01 rev v5.022`.
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
    final exe = _resolveExecutable(request.binary);
    final root = projectRoot.isNotEmpty
        ? projectRoot
        : (request.sourceFiles.isNotEmpty
              ? _dirname(request.sourceFiles.first)
              : '');
    final parser = VerilatorParser(rootPath: root);

    // SARIF only on a Verilator that writes it. The stderr transcript is
    // still collected and parsed on every run: it is the fallback when the
    // SARIF file is missing or unreadable, and the false-clean guard below
    // reads its `%Error` lines.
    Directory? sarifDir;
    String? sarifPath;
    if (outputMode == VerilatorOutputMode.auto && await _writesSarif(exe)) {
      try {
        sarifDir = await Directory.systemTemp.createTemp('lintcrux-verilator-');
        sarifPath = p.join(sarifDir.path, 'verilator.sarif');
      } on FileSystemException {
        sarifDir = null;
        sarifPath = null;
      }
    }
    try {
      yield* _runProcess(request, exe, root, parser, sarifPath);
    } finally {
      if (sarifDir != null) {
        try {
          await sarifDir.delete(recursive: true);
        } on FileSystemException {
          // A temp directory that will not delete is the OS's to reap.
        }
      }
    }
  }

  Future<bool> _writesSarif(String exe) async {
    final cached = _sarifSupport[exe];
    if (cached != null) return cached;
    final supported = versionWritesSarif(await _probeVersion(exe));
    _sarifSupport[exe] = supported;
    return supported;
  }

  Stream<Violation> _runProcess(
    LintRunRequest request,
    String exe,
    String root,
    VerilatorParser parser,
    String? sarifPath,
  ) async* {
    final args = _buildArgs(request, sarifPath: sarifPath);

    final LintProcess proc;
    try {
      proc = await runner.start(
        exe,
        args,
        // Spawn Verilator from the project root so relative source and
        // `+incdir+` paths resolve against the project directory, not the
        // process CWD (which for a Finder/Dock launch is `/`). Every other
        // engine already passes this; without it Verilator answers
        // `%Error: Cannot find file containing module` and lints nothing —
        // a silent false-clean.
        workingDirectory: root,
      );
    } on ProcessException catch (e) {
      throw EngineNotAvailableException(
        engineId: id,
        reason: 'could not start "$exe": ${e.message}',
        resolvedPath: exe,
        cause: e,
      );
    }
    _process = proc;

    // Verilator emits violations on stderr; stdout is typically empty
    // in --lint-only mode. We collect every line into a list so the
    // parser can do multi-line continuation matching, then flush as a
    // batch. Streaming per-violation requires header lookahead and is
    // not implemented. Read to end-of-file, not to the exit: warnings
    // that land after the exit code would otherwise be dropped, and a
    // run whose every line was dropped has no `%Error` left to fail on.
    final CapturedProcessOutput output;
    try {
      output = await collectProcessOutput(proc, engineId: id, executable: exe);
    } finally {
      _process = null;
    }
    final exitCode = output.exitCode;
    final stderrLines = output.stderr;
    final textViolations = parser.parse(stderrLines);
    final sarifViolations = sarifPath == null
        ? null
        : await _readSarif(sarifPath, root);
    // SARIF decides only when it parsed and agrees that there is something to
    // report or that there is nothing: a document with no results beside a
    // transcript that has findings is the text path's to settle.
    final violations =
        sarifViolations != null &&
            (sarifViolations.isNotEmpty || textViolations.isEmpty)
        ? sarifViolations
        : textViolations;

    // False-clean guard (mirrors the Verible engine's contract). Verilator
    // exits non-zero both when it FINDS lint violations and when the
    // invocation itself failed. A non-zero exit that produced NO parsed
    // violations *and* emitted a fatal `%Error:` line (e.g. a source file
    // it could not open, whose message carries no `file:line:col` for the
    // parser to lift) means the run linted nothing — surface it as an
    // engine failure so it shows red with the message rather than a green
    // "Completed, 0 violations".
    if (exitCode != 0 && violations.isEmpty) {
      final errorLines = stderrLines
          .where((l) => l.trimLeft().startsWith('%Error'))
          .toList(growable: false);
      if (errorLines.isNotEmpty) {
        throw EngineRunFailedException(
          engineId: id,
          exitCode: exitCode,
          reason: errorLines.first.trim(),
          outputExcerpt: stderrLines
              .where((l) => l.trim().isNotEmpty)
              .take(_kOutputExcerptLines)
              .toList(growable: false),
          resolvedPath: exe,
        );
      }
    }

    for (final v in violations) {
      yield v;
    }
  }

  @override
  void cancel() {
    final p = _process;
    if (p != null) {
      p.kill();
    }
  }

  /// Translate a [EngineBinaryConfig] into the executable name passed
  /// to the process runner.
  ///
  /// - `custom` honors the explicit path.
  /// - `bundled` asks [bundledBinaryResolver] for a per-platform
  ///   binary; if none is present (env var unset, file missing,
  ///   unsupported host arch), falls back to `system` so first-run
  ///   on contributor machines still works.
  /// - `system` resolves `verilator` from `PATH`.
  String _resolveExecutable(EngineBinaryConfig config) {
    switch (config.source) {
      case EngineBinarySource.custom:
        return config.path ?? 'verilator';
      case EngineBinarySource.bundled:
        return bundledBinaryResolver.resolve(id) ?? 'verilator';
      case EngineBinarySource.system:
        return 'verilator';
    }
  }

  /// Reads and parses the SARIF Verilator wrote to [path], or `null` when
  /// there is no usable document (see [VerilatorSarifParser.parse]).
  Future<List<Violation>?> _readSarif(String path, String root) async {
    final String source;
    try {
      // A missing file is a FileSystemException too.
      source = await File(path).readAsString();
    } on FileSystemException {
      return null;
    }
    String? realRoot;
    if (root.isNotEmpty) {
      try {
        realRoot = await Directory(root).resolveSymbolicLinks();
      } on FileSystemException {
        realRoot = null;
      }
    }
    return VerilatorSarifParser(
      rootPath: root,
      rootRealPath: realRoot,
    ).parse(source);
  }

  List<String> _buildArgs(LintRunRequest request, {String? sarifPath}) {
    final args = <String>['--lint-only'];
    if (sarifPath != null) {
      args
        ..add('--diagnostics-sarif-output')
        ..add(sarifPath);
    }
    for (final f in _resolveWarnFlags(request)) {
      args.add('-W$f');
    }
    for (final inc in request.includePaths) {
      args.add('+incdir+$inc');
    }
    request.defines.forEach((k, v) {
      if (v.isEmpty) {
        args.add('+define+$k');
      } else {
        args.add('+define+$k=$v');
      }
    });
    if (request.topModule != null && request.topModule!.isNotEmpty) {
      args
        ..add('--top-module')
        ..add(request.topModule!);
    }
    args
      ..addAll(request.binary.extraArgs)
      ..addAll(_stringListOption(request, 'extraOptions'))
      // Waiver/config files (`.vlt`) must precede the sources they
      // waive — the same ordering Edalize's Verilator backend uses.
      ..addAll(_stringListOption(request, 'waiverFiles'))
      ..addAll(request.sourceFiles);
    return args;
  }

  /// Reads a `List<String>` entry from the per-project options bag,
  /// returning an empty list when absent or mistyped. Used for the
  /// project-scoped `extraOptions` (raw CLI flags, e.g. `-G` parameter
  /// overrides from an EDAM import) and `waiverFiles` (`.vlt` config
  /// files) keys — both distinct from [EngineBinaryConfig.extraArgs],
  /// which is machine-scoped Settings state rather than project state.
  List<String> _stringListOption(LintRunRequest request, String key) {
    final raw = request.options[key];
    if (raw is! List) return const <String>[];
    return <String>[
      for (final entry in raw)
        if (entry is String && entry.isNotEmpty) entry,
    ];
  }

  /// Returns the `-W*` selector set to pass to Verilator, taking the
  /// per-project [LintRunRequest.options] bag's `warnFlags` value when
  /// present (must be a `List<String>`), or [defaultWarnFlags] otherwise.
  ///
  /// Mirrors `GhdlEngine._resolveWarnFlags`, including the explicit-empty-
  /// list semantics: `"warnFlags": []` means "opt-in warnings off", not
  /// "use the defaults".
  List<String> _resolveWarnFlags(LintRunRequest request) {
    final raw = request.options['warnFlags'];
    if (raw is List) {
      final out = <String>[];
      for (final entry in raw) {
        if (entry is String && entry.isNotEmpty) out.add(entry);
      }
      return out;
    }
    return defaultWarnFlags;
  }

  String _dirname(String filePath) {
    final i = filePath.lastIndexOf('/');
    if (i < 0) return '.';
    return filePath.substring(0, i);
  }
}
