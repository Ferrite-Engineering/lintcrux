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
import 'package:lintcrux/services/engines/slang/slang_parser.dart';

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
/// offers.
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
  /// slang output. Empty (the default) falls back to the directory of
  /// the first source file in the request.
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
    final args = _buildArgs(request, textMode: textMode);
    final root = projectRoot.isNotEmpty
        ? projectRoot
        : (request.sourceFiles.isNotEmpty
              ? _dirname(request.sourceFiles.first)
              : '');
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
    // that lands after it — the array's closing `]` is enough — would
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
    final violations = textMode
        ? parser.parseText(lines)
        : parser.parseJsonLines(lines);
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
    if (request.topModule != null && request.topModule!.isNotEmpty) {
      args
        ..add('--top')
        ..add(request.topModule!);
    }
    args
      ..addAll(request.binary.extraArgs)
      ..addAll(request.sourceFiles);
    return args;
  }

  String _dirname(String filePath) {
    final i = filePath.lastIndexOf('/');
    if (i < 0) return '.';
    return filePath.substring(0, i);
  }
}
