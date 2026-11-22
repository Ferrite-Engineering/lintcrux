// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/bundled_binary_resolver.dart';
import 'package:lintcrux/services/engines/engine_run_context.dart';
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
/// Three more keys in that bag change how GHDL is invoked, for designs the
/// default invocation cannot read. `std` (`87`, `93`, `93c`, `00`, `02`,
/// `08`, `19`) is passed as `--std=<value>`; without it GHDL uses its own
/// default, `93c`, and a VHDL-2008 design fails on its first
/// `ieee.float_pkg`. `syntaxOnly: true` runs `ghdl -s` in place of `ghdl -a`:
/// the same analysis and the same warnings without GHDL generating code for
/// every unit, which is what dominates the time on a large generated design
/// with an LLVM-backed GHDL. `extraOptions`, a `List<String>`, is appended
/// before the sources (`-frelaxed`, `-P<dir>`). GHDL analyses files in the
/// order given, so a unit's dependencies must come earlier in the project's
/// `sourceFiles`.
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
  /// GHDL output. Empty (the default) falls back to
  /// [LintRunRequest.projectRoot], then to the directory of the first source
  /// file in the request.
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
    final root = engineRootPath(request, configuredRoot: projectRoot);
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
    final unusable = <String>[];
    final violations = parser.parse(
      output.stderr,
      onUnrecognized: unusable.add,
    );
    for (final v in violations) {
      yield v;
    }
    final lost = unusable.where(_isLostDiagnostic).toList(growable: false);
    if (lost.isNotEmpty) {
      throw EngineRunFailedException(
        engineId: id,
        exitCode: output.exitCode,
        reason:
            'GHDL reported ${lost.length} problem(s) LintCrux could not '
            'place in a source file, so the findings above may be incomplete',
        outputExcerpt: lost.take(10).toList(growable: false),
        resolvedPath: exe,
      );
    }
  }

  /// The tool-level line GHDL prints after any failed analysis.
  static final RegExp _compilationErrorTrailer = RegExp(
    r'\bghdl(?:\.exe)?:\s*error:\s*compilation error\s*$',
    caseSensitive: false,
  );

  /// Any tool-level error, `ghdl:error: message`.
  static final RegExp _toolError = RegExp(
    r'\bghdl(?:\.exe)?:\s*error:',
    caseSensitive: false,
  );

  /// The header of a located diagnostic, `file:line:col:error: message`.
  static final RegExp _locatedDiagnostic = RegExp(
    r'^.+?:\d+(?::\d+)?:\s*(?:error|fatal|warning):',
  );

  /// Whether [line], which the parser could not use, was a finding or a
  /// failure rather than GHDL's chatter.
  ///
  /// `ghdl:error: compilation error` follows every analysis that found an
  /// error and says nothing new. Any other tool-level error
  /// (`ghdl:error: unknown command option '--x'`, an unknown `--std`) means
  /// GHDL did not analyse the design; a located error or warning whose path
  /// was refused is a finding that is not in the results.
  static bool _isLostDiagnostic(String line) {
    if (_compilationErrorTrailer.hasMatch(line)) return false;
    return _locatedDiagnostic.hasMatch(line) || _toolError.hasMatch(line);
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
    // `-s` analyses without generating code or updating the library.
    final syntaxOnly = request.options['syntaxOnly'] == true;
    final args = <String>[if (syntaxOnly) '-s' else '-a'];
    final std = _resolveStd(request);
    if (std != null) args.add('--std=$std');
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
      ..addAll(engineStringListOption(request, kExtraOptionsKey))
      ..addAll(request.sourceFiles);
    return args;
  }

  /// The `std` option, or `null` when the project sets none.
  ///
  /// A value that is not a non-empty string (`"std": 8`) is a mistake in the
  /// project file, and silently running GHDL's default standard instead would
  /// report a VHDL-2008 design as unreadable, so it fails the engine.
  String? _resolveStd(LintRunRequest request) {
    final raw = request.options['std'];
    if (raw == null) return null;
    if (raw is! String || raw.isEmpty) {
      throw EngineRunFailedException(
        engineId: id,
        exitCode: -1,
        reason:
            '"std" must be a VHDL standard string such as "08"; got '
            '${raw.runtimeType}',
      );
    }
    return raw;
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
}
