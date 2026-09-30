// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:lintcrux/core/cli/cli_args.dart';
import 'package:lintcrux/core/cli/cli_args_parser.dart';
import 'package:lintcrux/core/cli/cli_exit_codes.dart';
import 'package:lintcrux/domain/interfaces/violation_transformer.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/engine_run_status.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/baseline/baseline_filter.dart';
import 'package:lintcrux/services/engines/engine_binary_ids.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/parallel_engine_runner.dart';
import 'package:lintcrux/services/headless/cli_baseline_reader.dart';
import 'package:lintcrux/services/headless/headless_export_writer.dart';
import 'package:lintcrux/services/headless/headless_input_resolver.dart';
import 'package:lintcrux/services/headless/headless_run_result.dart';
import 'package:lintcrux/services/headless/project_config_overlay.dart';
import 'package:lintcrux/services/run/engine_run_planner.dart';
import 'package:lintcrux/services/telemetry/headless_telemetry.dart';
import 'package:lintcrux/services/transformers/pragma_waiver_transformer.dart';
import 'package:lintcrux/services/transformers/severity_override_transformer.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';
import 'package:lintcrux/services/waivers/pragma_waiver_reader.dart';

/// The headless lint pipeline: project in, exit code out.
///
/// This is what `bin/lintcrux.dart` is. It deliberately contains no
/// Flutter, no Riverpod and no window: the desktop app's
/// `LintRunNotifier` is a *provider* wrapper around the same
/// [EngineRunPlanner] + [ParallelEngineRunner] + transformer chain, so
/// both surfaces route the same source files to the same engines and
/// apply the same severity overrides and pragma waivers. If a CI gate
/// and the desktop app disagreed about a project's violation count, the
/// gate would be worthless.
///
/// The one seam that differs is the engine binary: the GUI resolves it
/// from Settings → Engines, which is a `shared_preferences`-backed store
/// with no meaning in a container. The CLI resolves from `PATH` unless a
/// `--<engine>-path` override is present.
///
/// ### What is intentionally *not* here
///
/// - **Managed waivers.** `WaiverStore` is Pro-tier and file-backed;
///   the open-core no-op store contributes nothing, so wiring it would
///   be dead weight. Source pragmas (`// verilator lint_off …`) *are*
///   honored, because `PragmaWaiverReader` is open-core and reads the
///   sources the run already touches.
/// - **The lint-run cache.** A CI job runs on a fresh checkout; a cache
///   whose backing store is Pro-tier and machine-local would never hit.
/// - **Custom regex rules.** The open-core evaluator is a no-op.
///
/// Each of those is a Pro overlay concern. The Pro CLI can layer them on
/// by constructing a [HeadlessRunner] with a richer [extraTransformers]
/// list; nothing here needs to change.
class HeadlessRunner {
  /// Creates a [HeadlessRunner].
  ///
  /// [registry] supplies the engines. [now] is injectable so tests get
  /// deterministic SARIF timestamps.
  HeadlessRunner({
    required this.registry,
    this.inputResolver = const HeadlessInputResolver(),
    this.configOverlay = const ProjectConfigOverlay(),
    this.baselineReader = const CliBaselineReader(),
    this.exportWriter = const HeadlessExportWriter(),
    this.pragmaReader = const PragmaWaiverReader(),
    this.extraTransformers = const <ViolationTransformer>[],
    this.engineTimeout = const Duration(seconds: 300),
    this.telemetry,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Engines available to this invocation.
  final EngineRegistry registry;

  /// Turns positional arguments into a project.
  final HeadlessInputResolver inputResolver;

  /// Applies `--config`.
  final ProjectConfigOverlay configOverlay;

  /// Reads the baseline for `--fail-on-new-violations`.
  final CliBaselineReader baselineReader;

  /// Writes the `--export` artifact.
  final HeadlessExportWriter exportWriter;

  /// Reads `lint_off` / `lint_on` pragma ranges out of the sources.
  final PragmaWaiverReader pragmaReader;

  /// Extra transformers appended after the open-core chain. The Pro
  /// overlay's CLI passes its managed-waiver transformer here.
  final List<ViolationTransformer> extraTransformers;

  /// The headless telemetry reporter, or `null` when the caller does not
  /// want one.
  ///
  /// `LintcruxCli` resolves it from the on-disk consent store and passes it
  /// here; a `null` reporter — or one whose `transmits` is false, which is
  /// every machine that has not stored an affirmative consent — makes every
  /// call below a no-op. The runner never resolves consent itself, so a caller
  /// that constructs a `HeadlessRunner` directly (every test in this
  /// repository does) cannot accidentally transmit.
  final HeadlessTelemetry? telemetry;

  /// Per-engine wall-clock budget. Larger than the GUI default (120 s)
  /// because a CI runner is slower than a workstation and a watchdog
  /// kill reports as a run failure, which fails the build.
  final Duration engineTimeout;

  final DateTime Function() _now;

  /// Printed when language routing left every engine with nothing to
  /// look at — e.g. a VHDL-only project with only Verilator enabled.
  /// Reported as a run failure: zero engines ran, so "0 violations"
  /// would be a lie of omission.
  static const String _noCompatibleSourcesMessage =
      'No engine had a compatible source file to lint. Check the '
      "project's language declarations and enabledEngineIds.";

  /// Runs the pipeline described by [args].
  ///
  /// Never throws: every failure path is folded into a
  /// [HeadlessRunResult] carrying a [CliExitCode] and human-readable
  /// [HeadlessRunResult.problems].
  Future<HeadlessRunResult> run(CliArgs args) async {
    // ── 1. Resolve the input ───────────────────────────────────────
    final resolution = await inputResolver.resolve(
      args.paths,
      topModule: args.topModule,
    );
    if (!resolution.isSuccess) {
      // Distinguish "you typed something unusable" (usage) from "the
      // thing you named is broken" (run failure). Both used to be a
      // silent clean run.
      return HeadlessRunResult.failed(
        code: switch (resolution.kind) {
          HeadlessInputFailureKind.usage => CliExitCode.usage,
          HeadlessInputFailureKind.loadFailed => CliExitCode.runFailed,
        },
        problems: resolution.problems,
      );
    }
    var project = resolution.project!;

    // ── 2. Apply --config ──────────────────────────────────────────
    final configPath = args.configPath;
    if (configPath != null && configPath.isNotEmpty) {
      try {
        project = await configOverlay.applyFile(project, configPath);
      } on ProjectConfigOverlayException catch (e) {
        return HeadlessRunResult.failed(
          code: CliExitCode.runFailed,
          problems: <String>[e.message],
        );
      }
    }

    // ── 3. Plan the run ────────────────────────────────────────────
    const planner = EngineRunPlanner();
    final plan = planner.plan(
      project: project,
      registry: registry,
      engineIdsOverride: args.engineIds,
      topModuleOverride: args.topModule,
      binaryConfigFor: (engineId) => _binaryFor(engineId, args),
    );

    if (plan.unknownEngineIds.isNotEmpty) {
      final unknown = plan.unknownEngineIds.join(', ');
      final known = registry.engineIds.join(', ');
      return HeadlessRunResult.failed(
        code: CliExitCode.usage,
        problems: <String>[
          'Unknown engine id(s): $unknown. Registered engines: $known.',
        ],
      );
    }

    final diagnostics = <String>[
      for (final id in plan.enginesWithoutSources)
        'engine "$id" received no compatible source files and was skipped',
    ];

    if (plan.pairs.isEmpty) {
      // Nothing to run is a run failure, not a clean bill of health.
      return HeadlessRunResult.failed(
        code: CliExitCode.runFailed,
        problems: const <String>[_noCompatibleSourcesMessage],
        diagnostics: diagnostics,
      );
    }

    // ── 4. Build the transformer chain ─────────────────────────────
    // Same order as LintRunNotifier._buildTransformer: severity
    // overrides, then source pragmas, then anything the caller layered
    // on (the Pro managed-waiver transformer).
    final pragmaRanges = await pragmaReader.readFiles(project.sourceFiles);
    final transformer = CompositeViolationTransformer(<ViolationTransformer>[
      SeverityOverrideTransformer(project.severityOverrides),
      PragmaWaiverTransformer(pragmaRanges),
      ...extraTransformers,
    ]);

    // ── 5. Run the engines ─────────────────────────────────────────
    final store = InMemoryViolationStore();
    final runner = ParallelEngineRunner(
      store,
      transformer: transformer,
      engineTimeout: engineTimeout,
      // The same seam the desktop app binds, so a CI run and a workstation run
      // report `engine.run` identically. `EngineRunOutcome` is the reason this
      // is a callback and not derived from `runner.statuses` afterwards: a
      // watchdog kill and a crash are both `EngineRunPhase.failed`, and
      // the `engine.run` counter needs them apart.
      onOutcome: telemetry?.recordEngineOutcome,
    );
    try {
      await runner.runAll(plan.pairs);
    } finally {
      await runner.dispose();
    }

    final statuses = Map<String, EngineRunStatus>.unmodifiable(runner.statuses);
    final violations = List<Violation>.unmodifiable(store.all);

    // `trigger: cli` — the telemetry dimension the headless path exists to
    // fill. Emitted after the engines settle and before the exit-code
    // classification, so it counts a run that happened rather than a run that
    // passed: an engine mix that fails is exactly as interesting as one that
    // succeeds.
    telemetry?.recordRunCompleted(engines: plan.pairs.length);

    // ── 6. Classify engine failures ────────────────────────────────
    final problems = <String>[];
    for (final status in statuses.values) {
      switch (status.phase) {
        case EngineRunPhase.failed:
          problems.add(
            'engine "${status.engineId}" failed: '
            '${status.error ?? 'no diagnostic available'}',
          );
        case EngineRunPhase.unavailable:
          final message =
              'engine "${status.engineId}" is unavailable: '
              '${status.error ?? 'binary not found'}';
          if (args.allowMissingEngines) {
            diagnostics.add('$message (skipped: --allow-missing-engines)');
          } else {
            // Name only a flag that exists: CDC runs Yosys and reads
            // --yosys-path, and an engine without a path flag gets none.
            final binaryId = binaryEngineIdFor(status.engineId);
            final pointAtIt =
                CliArgsParser.binaryPathEngineIds.contains(binaryId)
                ? 'point at it with --$binaryId-path, '
                : '';
            problems.add(
              '$message. Install it, $pointAtIt'
              'drop it with --engine, or pass '
              '--allow-missing-engines to tolerate its absence.',
            );
          }
        case EngineRunPhase.cancelled:
          problems.add('engine "${status.engineId}" was cancelled');
        case EngineRunPhase.idle:
        case EngineRunPhase.running:
          problems.add(
            'engine "${status.engineId}" never reached a terminal state',
          );
        case EngineRunPhase.completed:
          break;
      }
    }

    // ── 7. Baseline classification ─────────────────────────────────
    final reportable = <Violation>[
      for (final v in violations)
        if (!v.isSuppressed) v,
    ];
    final suppressedCount = violations.length - reportable.length;

    var newViolations = const <Violation>[];
    var persisting = const <Violation>[];
    var resolvedCount = 0;
    String? baselinePath;
    var baselineApplied = false;

    if (args.failOnNewViolations) {
      baselinePath = CliBaselineReader.resolvePath(
        projectRoot: project.rootPath,
        explicitPath: args.baselinePath,
      );
      final read = await baselineReader.read(baselinePath);
      if (read.isCorrupt) {
        // A gate that cannot read its baseline must not pass silently:
        // BaselineFilter would treat "no baseline" as "everything new",
        // which is strict, but the *user* asked to compare against a
        // file that exists and is broken. Surface it.
        problems.add(
          'could not read baseline $baselinePath: ${read.error}',
        );
      } else if (!read.hasBaseline) {
        diagnostics.add(
          'no baseline at $baselinePath — every violation counts as new. '
          'Set one from LintCrux Pro (Tools → Set Baseline) and commit it.',
        );
      }
      baselineApplied = read.hasBaseline;
      final delta = BaselineFilter.classify(
        current: reportable,
        baseline: read.baseline,
        projectRoot: project.rootPath,
      );
      newViolations = delta.newViolations;
      persisting = delta.persistingViolations;
      resolvedCount = delta.resolvedViolations.length;
    }

    // ── 8. Export ──────────────────────────────────────────────────
    String? exportPath;
    final format = args.exportFormat;
    final outPath = args.exportOutputPath;
    if (format != null && outPath != null) {
      try {
        await exportWriter.write(
          violations: violations,
          format: format,
          outputPath: outPath,
          projectRoot: project.rootPath,
          runId: project.name,
          exportTime: _now(),
        );
        exportPath = outPath;
      } on HeadlessExportException catch (e) {
        problems.add(e.message);
      }
    }

    // ── 9. Map to an exit code ─────────────────────────────────────
    final exitCode = _exitCodeFor(
      args: args,
      problems: problems,
      reportable: reportable,
      newViolations: newViolations,
    );

    return HeadlessRunResult(
      exitCode: exitCode,
      violations: violations,
      newViolations: newViolations,
      persistingViolations: persisting,
      resolvedViolationCount: resolvedCount,
      suppressedCount: suppressedCount,
      statuses: statuses,
      problems: problems,
      diagnostics: diagnostics,
      baselinePath: baselinePath,
      baselineApplied: baselineApplied,
      exportPath: exportPath,
      projectName: project.name,
    );
  }

  /// The escalation order of the exit-code contract, in one place.
  ///
  /// Run failure outranks everything: the violation count from a run
  /// where an engine died is a partial result, and reporting `0` for it
  /// is the exact defect this whole layer exists to prevent.
  ///
  /// Below that, the **organization's ceiling** (code 4) comes next. It is
  /// the outer constraint: being above it blocks whether or not this change
  /// caused it, while a regression that stays under it is a softer signal.
  /// Then the more specific team gate (`--fail-on-new-violations`, code 2)
  /// beats the blunt one (`--exit-code`, code 1) so a CI job can tell a
  /// regression from pre-existing debt.
  ///
  /// The threshold needs no flag to arm it. Unlike the two gates below it,
  /// which are opt-in because a bare `lintcrux project.lintcrux` is a
  /// reporting command rather than a gate, a configured org ceiling is
  /// already an explicit statement by an administrator — asking the pipeline
  /// to opt in to it as well would let a pipeline opt out.
  static int _exitCodeFor({
    required CliArgs args,
    required List<String> problems,
    required List<Violation> reportable,
    required List<Violation> newViolations,
  }) {
    if (problems.isNotEmpty) return CliExitCode.runFailed;
    final threshold = args.ciGateThreshold;
    if (threshold != null && reportable.length > threshold) {
      return CliExitCode.overThreshold;
    }
    if (args.failOnNewViolations && newViolations.isNotEmpty) {
      return CliExitCode.newViolations;
    }
    if (args.exitCodeOnFindings && reportable.isNotEmpty) {
      return CliExitCode.violations;
    }
    return CliExitCode.clean;
  }

  /// Resolves the binary for [engineId].
  ///
  /// `--<engine>-path` wins; otherwise `PATH`. There is deliberately no
  /// `bundled` fallback here: no engine binaries ship with LintCrux
  /// today, and `EngineBinarySource.bundled` silently degrades to a
  /// `PATH` lookup, which would make a CI failure look like a resolver
  /// bug rather than a missing install.
  static EngineBinaryConfig _binaryFor(String engineId, CliArgs args) {
    final override = args.engineBinaryPaths[engineId];
    if (override != null && override.isNotEmpty) {
      return EngineBinaryConfig(
        source: EngineBinarySource.custom,
        path: override,
      );
    }
    return const EngineBinaryConfig.system();
  }
}
