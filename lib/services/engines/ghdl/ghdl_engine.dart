// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/bundled_binary_resolver.dart';
import 'package:lintcrux/services/engines/ghdl/ghdl_availability_service.dart';
import 'package:lintcrux/services/engines/ghdl/ghdl_parser.dart';
import 'package:lintcrux/services/engines/process_runner.dart';

/// LintCrux [LintEngine] wrapper around GHDL.
///
/// GHDL has no native lint mode. The classic invocation
/// `ghdl -a <sources>; ghdl -e <top>; ghdl -r <top> --warn-*` analyses,
/// elaborates, and "runs" the design with the warning set enabled;
/// every selected `--warn-*` flag emits its findings to stderr in the
/// compiler-style shape [GhdlParser] consumes. LintCrux invokes the
/// analyse step only — that's enough to surface the warning class
/// LintCrux cares about without paying for elaboration on large
/// designs. The elaboration / run steps remain available behind the
/// `runElaboration` and `runSimulate` option flags for users who want
/// the deeper warning set (binding, vital generics, etc.) at the cost
/// of additional runtime.
///
/// Warning-flag configuration lives in `LintRunRequest.options` under
/// the `warnFlags` key — a `List<String>` of GHDL `--warn-*` names
/// without the leading `--warn-` (e.g. `['binding', 'reserved',
/// 'default-binding']`). The engine prepends `--warn-` and passes them
/// through. The `.lintcrux` per-engine options bag persists the choice
/// per project.
///
/// Binary resolution prefers the [GhdlAvailabilityService]
/// (bundled cache → PATH); custom paths from
/// [EngineBinaryConfig.source] = [EngineBinarySource.custom] take
/// precedence. Missing-binary cases surface as
/// [EngineNotAvailableException] either on the returned stream or as a
/// `null` from [detectVersion].
class GhdlEngine implements LintEngine {
  /// Creates a [GhdlEngine].
  GhdlEngine({
    this.runner = const SystemProcessRunner(),
    this.projectRoot = '',
    this.bundledBinaryResolver = const BundledBinaryResolver(),
    GhdlAvailabilityService? availabilityService,
  }) : availabilityService =
           availabilityService ?? const GhdlAvailabilityService();

  /// The process runner. Tests inject a fake; production uses
  /// [SystemProcessRunner].
  final ProcessRunner runner;

  /// Absolute project root used to resolve relative paths reported in
  /// GHDL output. Empty (the default) falls back to the directory of
  /// the first source file in the request.
  final String projectRoot;

  /// Bundled-binary resolver consulted when [EngineBinaryConfig.source]
  /// is [EngineBinarySource.bundled].
  final BundledBinaryResolver bundledBinaryResolver;

  /// Bundled-or-PATH GHDL availability probe. Consulted by [detectVersion]
  /// and by the executable resolver as the implicit `bundled` source.
  final GhdlAvailabilityService availabilityService;

  /// The default `--warn-*` flag set used when the per-project options
  /// bag does not declare an explicit `warnFlags` list. Mirrors the
  /// useful-by-default set commonly recommended for VHDL housekeeping.
  static const List<String> defaultWarnFlags = <String>[
    'binding',
    'reserved',
    'default-binding',
    'library',
    'shared',
    'hide',
    'unused',
    'others',
    'pure',
  ];

  LintProcess? _process;

  @override
  String get id => 'ghdl';

  @override
  String get displayName => 'GHDL';

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.vhdl},
    // GHDL elaboration is whole-project — incremental re-linting
    // a single .vhd file would miss cross-file binding
    // diagnostics that emerge during a fresh analysis pass. Stay
    // at the default (false) so the orchestrator falls back to a
    // full run on every change.
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
      // `ghdl --version` prints a multi-line block; the first
      // non-empty line is the version banner (e.g.
      // `GHDL 4.1.0 (Ubuntu)`).
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
    final args = _buildArgs(request);
    final root = projectRoot.isNotEmpty
        ? projectRoot
        : (request.sourceFiles.isNotEmpty
              ? _dirname(request.sourceFiles.first)
              : '');
    final parser = GhdlParser(rootPath: root);

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

    // GHDL emits diagnostics on stderr in analyse mode. Stdout is
    // typically empty for `ghdl -a` but we drain it to avoid the pipe
    // filling up. Both are read to end-of-file, not to the exit: this
    // engine does not consult the exit code, so diagnostics that land
    // after it would otherwise parse as a clean run.
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
    final violations = parser.parse(output.stderr);
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

  /// Resolve the GHDL executable per [EngineBinaryConfig.source]:
  ///
  /// - `custom` → honor the explicit path.
  /// - `bundled` → ask the resolver; fall back to the availability
  ///   service's combined bundled-or-PATH probe; final fallback is the
  ///   literal `'ghdl'`.
  /// - `system` → `'ghdl'`.
  String _resolveExecutable(EngineBinaryConfig config) {
    switch (config.source) {
      case EngineBinarySource.custom:
        return config.path ?? 'ghdl';
      case EngineBinarySource.bundled:
        final bundled = bundledBinaryResolver.resolve(id);
        if (bundled != null) return bundled;
        return availabilityService.resolveBinaryPath() ?? 'ghdl';
      case EngineBinarySource.system:
        return 'ghdl';
    }
  }

  List<String> _buildArgs(LintRunRequest request) {
    final args = <String>['-a'];
    final warnFlags = _resolveWarnFlags(request);
    for (final f in warnFlags) {
      args.add('--warn-$f');
    }
    // `+incdir+` / `+define+` syntax is Verilog territory; GHDL doesn't
    // accept them. They are intentionally dropped here — VHDL doesn't
    // have a preprocessor, and include paths are not how GHDL resolves
    // sources. Per-source-file libraries map onto `--work=<lib>` which
    // is not implemented; every file is analysed into `work`.
    args
      ..addAll(request.binary.extraArgs)
      ..addAll(request.sourceFiles);
    return args;
  }

  /// Returns the `--warn-*` flag set to pass to GHDL, taking the
  /// per-project [LintRunRequest.options] bag's `warnFlags` value when
  /// present (must be a `List<String>`), or [defaultWarnFlags]
  /// otherwise.
  List<String> _resolveWarnFlags(LintRunRequest request) {
    final raw = request.options['warnFlags'];
    if (raw is List) {
      final out = <String>[];
      for (final entry in raw) {
        if (entry is String && entry.isNotEmpty) out.add(entry);
      }
      // Treat an explicit empty list as "disable every warning" rather
      // than "use defaults" — power users disabling all warnings still
      // want a clean analyse pass for syntactic correctness.
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
