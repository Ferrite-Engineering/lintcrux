// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/bundled_binary_resolver.dart';
import 'package:lintcrux/services/engines/engine_run_context.dart';
import 'package:lintcrux/services/engines/process_runner.dart';
import 'package:lintcrux/services/engines/slang/slang_parser.dart';
import 'package:path/path.dart' as p;

/// LintCrux [LintEngine] wrapper around `slang` (the open-source
/// SystemVerilog compiler).
///
/// The engine prefers slang's JSON diagnostics mode so the parser does
/// not have to disambiguate the source-context lines of the text
/// surface. That mode is `--diag-json <file|->`, added upstream in
/// slang 8.0; `-` selects stdout. `-q` is passed alongside it to
/// suppress the human-readable banner slang otherwise interleaves with
/// the JSON on stdout (`Top level design units:` … `Build succeeded:
/// …`) — the parser tolerates the banner either way, but suppressing it
/// keeps the transcript clean.
///
/// There is no `--json-diagnostics` flag and there never has been —
/// slang rejects it outright (`error: unknown command line argument`),
/// which made every JSON-mode run a zero-violation failure. Verified
/// against slang 11.0.0 and against upstream's `Driver.cpp` at tags
/// v3.0 through v11.0.
///
/// The `textModeFallback: true` option in [LintRunRequest.options]
/// forces the text parser, which is the only surface slang < 8.0
/// offers. `extraOptions`, a `List<String>` in the same bag, is appended to
/// the command line before the sources, for flags a project needs that have
/// no option of their own (`--allow-toplevel-iface-ports`, `--std`).
///
/// slang runs in the project root ([LintRunRequest.projectRoot]), and prints
/// each file in a diagnostic relative to where it ran. A source or include
/// path outside the root would come back as `../other/x.sv`, and a path that
/// climbs out of the root is refused, so a run with one is given
/// `--diag-abs-paths`. A diagnostic that is refused anyway, or that slang
/// reported without a location, fails the run ([EngineRunFailedException])
/// rather than disappearing: a run that lost findings must not read as clean.
///
/// The binary resolves from `PATH` (system source); bundled per-platform
/// binaries do not ship yet, and custom paths come from the Settings → Engines
/// UI. Missing-binary cases surface as [EngineNotAvailableException] on the
/// returned stream, or as a `null` from [detectVersion].
class SlangEngine implements LintEngine {
  /// Creates a [SlangEngine].
  SlangEngine({
    this.runner = const SystemProcessRunner(),
    this.projectRoot = '',
    this.bundledBinaryResolver = const BundledBinaryResolver(),
  });

  /// The process runner. Tests inject a fake; production uses
  /// [SystemProcessRunner].
  final ProcessRunner runner;

  /// Absolute project root used to resolve relative paths reported in
  /// slang output. Empty (the default) falls back to
  /// [LintRunRequest.projectRoot], then to the directory of the first source
  /// file in the request.
  final String projectRoot;

  /// Bundled-binary resolver, consulted when [EngineBinaryConfig.source]
  /// is [EngineBinarySource.bundled].
  final BundledBinaryResolver bundledBinaryResolver;

  LintProcess? _process;

  @override
  String get id => 'slang';

  @override
  String get displayName => 'Slang';

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.systemVerilog, HdlLanguage.verilog},
    emitsStructuredOutput: true,
    // Slang accepts a caller-supplied file list per invocation and
    // performs its own parse/elaborate cycle per call. Scoping
    // the file list to just the changed file(s) is a meaningful
    // speedup on large SoC projects.
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
    final exe = _resolveExecutable(request.binary);
    final textMode = request.options['textModeFallback'] == true;
    final root = engineRootPath(request, configuredRoot: projectRoot);
    final args = _buildArgs(request, root: root, textMode: textMode);
    final parser = SlangParser(rootPath: root);

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

    // Slang emits text diagnostics on stderr (compiler convention) and
    // the `--diag-json -` array on stdout; we collect both so neither
    // path silently drops violations. Both are read to end-of-file, not
    // to the exit: this engine does not consult the exit code, so output
    // that lands after it (the array's closing `]` is enough) would
    // otherwise parse as a clean run.
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
    final lines = <String>[...output.stdout, ...output.stderr];
    final unusable = <String>[];
    final violations = textMode
        ? parser.parseText(lines, onUnrecognized: unusable.add)
        : parser.parseJsonLines(lines, onUnrecognized: unusable.add);
    for (final v in violations) {
      yield v;
    }
    final lost = unusable.where(_isLostDiagnostic).toList(growable: false);
    if (lost.isNotEmpty) {
      throw EngineRunFailedException(
        engineId: id,
        exitCode: output.exitCode,
        reason:
            '${lost.length} slang diagnostic(s) could not be placed in a '
            'source file or were not diagnostics of the design, so the '
            'findings above may be incomplete',
        outputExcerpt: lost.take(10).toList(growable: false),
        resolvedPath: exe,
      );
    }
  }

  /// Whether any of [paths] lies outside [root].
  static bool _reachesOutside(String root, Iterable<String> paths) {
    if (root.isEmpty) return false;
    return paths.any(
      (path) => !p.isWithin(root, p.normalize(p.join(root, path))),
    );
  }

  /// The header of a located diagnostic, `file:line:col: error: message`.
  static final RegExp _locatedDiagnostic = RegExp(
    r'^.+?:\d+:\d+:\s+(?:error|fatal error|fatal|warning):',
  );

  /// slang's own command-line complaints, which carry no location
  /// (`error: unknown command line argument '--x'`).
  static final RegExp _driverError = RegExp('^(?:fatal )?error:');

  /// Whether [line], which the parser could not use, was a finding or a
  /// failure rather than slang's chatter.
  ///
  /// Anything else the parser skips (notes, banners, source context) loses
  /// nothing. These do: a located error or warning whose path was refused, a
  /// JSON diagnostic with no usable location or that is not JSON at all, and
  /// a driver error, after which slang analysed nothing.
  static bool _isLostDiagnostic(String line) {
    final text = line.trimLeft();
    if (text.startsWith('{') || text.startsWith('[')) {
      try {
        final decoded = json.decode(text);
        final severity = decoded is Map ? decoded['severity'] : null;
        return severity is String &&
            const {'error', 'fatal', 'warning'}.contains(severity);
      } on FormatException {
        return true;
      }
    }
    return _locatedDiagnostic.hasMatch(line) || _driverError.hasMatch(line);
  }

  @override
  void cancel() {
    final p = _process;
    if (p != null) {
      p.kill();
    }
  }

  /// Translate a [EngineBinaryConfig] into the executable name passed
  /// Translate a [EngineBinaryConfig] into the executable name passed
  /// to the process runner. `bundled` asks the resolver for a
  /// per-platform binary, falling back to `system` on miss.
  String _resolveExecutable(EngineBinaryConfig config) {
    switch (config.source) {
      case EngineBinarySource.custom:
        return config.path ?? 'slang';
      case EngineBinarySource.bundled:
        return bundledBinaryResolver.resolve(id) ?? 'slang';
      case EngineBinarySource.system:
        return 'slang';
    }
  }

  List<String> _buildArgs(
    LintRunRequest request, {
    required String root,
    required bool textMode,
  }) {
    final args = <String>[];
    if (!textMode) {
      // `--diag-json -` writes the diagnostic array to stdout; `-q`
      // drops the surrounding banner. Both exist in slang 8.0+.
      args
        ..add('-q')
        ..add('--diag-json')
        ..add('-');
    }
    // A file outside the folder slang runs in would be reported as `../x.sv`.
    if (_reachesOutside(root, [
      ...request.sourceFiles,
      ...request.includePaths,
    ])) {
      args.add('--diag-abs-paths');
    }
    for (final inc in request.includePaths) {
      args
        ..add('-I')
        ..add(inc);
    }
    request.defines.forEach((k, v) {
      if (v.isEmpty) {
        args.add('-D$k');
      } else {
        args.add('-D$k=$v');
      }
    });
    // Top-level parameter overrides.
    request.parameters.forEach((k, v) {
      args
        ..add('-G')
        ..add('$k=$v');
    });
    if (request.topModule != null && request.topModule!.isNotEmpty) {
      args
        ..add('--top')
        ..add(request.topModule!);
    }
    args
      ..addAll(request.binary.extraArgs)
      ..addAll(engineStringListOption(request, kExtraOptionsKey))
      ..addAll(request.sourceFiles);
    return args;
  }
}
