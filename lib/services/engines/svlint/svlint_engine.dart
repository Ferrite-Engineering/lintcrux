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
import 'package:lintcrux/services/engines/svlint/svlint_parser.dart';

/// LintCrux [LintEngine] wrapper around `svlint`.
///
/// Svlint is the lightweight SystemVerilog linter from the dalance/svlint
/// project — focused on the synthesizable subset, configured via a
/// project-root `.svlint.toml` file. The engine prefers
/// `--output-format=json`; older builds without JSON support fall back
/// to the text parser via the `textModeFallback` option.
///
/// `.svlint.toml` detection: when the project root
/// ([LintRunRequest.projectRoot]) contains a `.svlint.toml`, the engine
/// adds `--config <path>` so svlint applies the project's rule selection
/// even to sources that live outside the root. Overridden when the caller
/// sets `configPath` in [LintRunRequest.options].
///
/// Binary resolution follows the standard
/// custom → bundled → PATH chain. Missing-binary cases surface as
/// [EngineNotAvailableException].
class SvlintEngine implements LintEngine {
  /// Creates a [SvlintEngine].
  SvlintEngine({
    this.runner = const SystemProcessRunner(),
    this.projectRoot = '',
    this.bundledBinaryResolver = const BundledBinaryResolver(),
  });

  /// The process runner. Tests inject a fake; production uses
  /// [SystemProcessRunner].
  final ProcessRunner runner;

  /// Fallback project root, used to resolve relative paths in engine
  /// output and to discover `.svlint.toml` when a request carries no
  /// [LintRunRequest.projectRoot].
  final String projectRoot;

  /// Bundled-binary resolver consulted when [EngineBinaryConfig.source]
  /// is [EngineBinarySource.bundled].
  final BundledBinaryResolver bundledBinaryResolver;

  LintProcess? _process;

  @override
  String get id => 'svlint';

  @override
  String get displayName => 'Svlint';

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {
      HdlLanguage.systemVerilog,
      HdlLanguage.verilog,
    },
    emitsStructuredOutput: true,
    supportsConfigFile: true,
    // Svlint is per-file and could in principle support
    // incremental re-runs (it has no project-wide analysis), but
    // we hold its capability flag at the default `false` until
    // its per-rule output handling has been confirmed to behave
    // correctly under partial-file invocation. Revisit when the
    // incremental flow has accumulated production usage.
  );

  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) => run(request);

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
    final parser = SvlintParser(rootPath: root);

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

    // Svlint emits violations on stdout; errors and diagnostics go to
    // stderr. Drain both so the pipe doesn't stall, and read both to
    // end-of-file, not to the exit: this engine does not consult the exit
    // code, so findings that land after it would otherwise parse as a
    // clean run.
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

  /// Whether [root] (the request's project root, else the constructor's
  /// [projectRoot]) contains a `.svlint.toml` config file. Public for
  /// tests; production callers shouldn't need this.
  bool projectHasConfigFile([String? root]) => resolveConfigPath(root) != null;

  /// Returns the absolute `.svlint.toml` path in [root] (the request's
  /// project root, else the constructor's [projectRoot]), or `null` if not
  /// present. Used by [_buildArgs] to populate the `--config` flag and
  /// exposed for tests / diagnostics.
  String? resolveConfigPath([String? root]) {
    final dir = (root != null && root.isNotEmpty) ? root : projectRoot;
    if (dir.isEmpty) return null;
    final path = dir.endsWith('/') ? '$dir.svlint.toml' : '$dir/.svlint.toml';
    return File(path).existsSync() ? path : null;
  }

  String _resolveExecutable(EngineBinaryConfig config) {
    switch (config.source) {
      case EngineBinarySource.custom:
        return config.path ?? 'svlint';
      case EngineBinarySource.bundled:
        return bundledBinaryResolver.resolve(id) ?? 'svlint';
      case EngineBinarySource.system:
        return 'svlint';
    }
  }

  List<String> _buildArgs(
    LintRunRequest request, {
    required bool textMode,
  }) {
    final args = <String>[];
    if (!textMode) {
      // Svlint emits one JSON object per finding in JSON mode.
      args
        ..add('--output-format')
        ..add('json');
    }
    final explicitConfig = request.options['configPath'];
    final configPath = explicitConfig is String && explicitConfig.isNotEmpty
        ? explicitConfig
        : resolveConfigPath(request.projectRoot);
    if (configPath != null) {
      args
        ..add('--config')
        ..add(configPath);
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
