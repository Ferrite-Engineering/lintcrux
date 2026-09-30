// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/core/cli/cli_args.dart';
import 'package:lintcrux/core/cli/cli_args_provider.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/interfaces/violation_transformer.dart';
import 'package:lintcrux/domain/models/app_settings.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/engine_run_outcome.dart';
import 'package:lintcrux/domain/models/engine_run_status.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/services/engines/engine_language_router.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';
import 'package:lintcrux/services/engines/engine_watchdog_provider.dart';
import 'package:lintcrux/services/engines/parallel_engine_runner.dart';
import 'package:lintcrux/services/lint_cache/lint_cache_enabled_provider.dart';
import 'package:lintcrux/services/lint_cache/lint_run_cache_service_provider.dart';
import 'package:lintcrux/services/rules/custom_rule_evaluator.dart';
import 'package:lintcrux/services/run/engine_run_planner.dart';
import 'package:lintcrux/services/run/lint_run_lifecycle.dart';
import 'package:lintcrux/services/telemetry/telemetry_event_catalog.dart';
import 'package:lintcrux/services/transformers/managed_waiver_transformer.dart';
import 'package:lintcrux/services/transformers/pragma_waiver_transformer.dart';
import 'package:lintcrux/services/transformers/severity_override_transformer.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';
import 'package:lintcrux/services/waivers/pragma_waiver_reader.dart';
import 'package:lintcrux/services/waivers/waiver_store_provider.dart';

/// Aggregated run state exposed to the UI.
///
/// Immutable. The notifier is re-hosted in each tab's
/// `ProviderContainer`, so each tab carries its own run state without
/// leaking across tabs.
class LintRunState {
  /// Creates a [LintRunState].
  const LintRunState({
    this.statuses = const <String, EngineRunStatus>{},
    this.isRunning = false,
    this.runStartedAt,
    this.runFinishedAt,
  });

  /// Empty initial state.
  static const LintRunState idle = LintRunState();

  /// Per-engine status, keyed by engine id.
  final Map<String, EngineRunStatus> statuses;

  /// Whether the orchestrator is currently mid-run.
  final bool isRunning;

  /// When the most recent run started.
  final DateTime? runStartedAt;

  /// When the most recent run finished. `null` while still running.
  final DateTime? runFinishedAt;

  /// Status for [engineId], or `null` if [engineId] wasn't part of the
  /// most recent run.
  EngineRunStatus? statusFor(String engineId) => statuses[engineId];

  /// Returns a copy with overridden fields.
  LintRunState copyWith({
    Map<String, EngineRunStatus>? statuses,
    bool? isRunning,
    DateTime? runStartedAt,
    DateTime? runFinishedAt,
  }) {
    return LintRunState(
      statuses: statuses ?? this.statuses,
      isRunning: isRunning ?? this.isRunning,
      runStartedAt: runStartedAt ?? this.runStartedAt,
      runFinishedAt: runFinishedAt ?? this.runFinishedAt,
    );
  }
}

/// Riverpod notifier that drives the [ParallelEngineRunner] from the UI.
///
/// The notifier owns the runner instance for the lifetime of the
/// provider; on dispose it cancels any active run and disposes the
/// runner's status stream so listeners do not leak.
///
/// The provider is rebound in every tab's `ProviderContainer`; the
/// notifier's API is the same at either scope.
class LintRunNotifier extends Notifier<LintRunState> {
  ParallelEngineRunner? _runner;
  StreamSubscription<EngineRunStatus>? _statusSub;

  /// Claimed synchronously by [runAll] and [runIncremental], before their
  /// first await. [LintRunState.isRunning] is only set once the transformer
  /// has read every source file, so a second trigger inside that window (Run
  /// pressed as a project opens, auto-reload just after an open) used to
  /// start a second run over the first.
  bool _claimed = false;

  /// Runs [body] as the one run in flight, or not at all.
  ///
  /// A run that throws still ends: `isRunning` is cleared, so Run, Cancel and
  /// auto-reload keep working, and the error goes on to the zone to be
  /// logged. It used to stay set for the rest of the tab's life.
  Future<void> _asTheOnlyRun(Future<void> Function() body) async {
    if (state.isRunning || _claimed) return;
    _claimed = true;
    try {
      await body();
    } on Object {
      if (ref.mounted && state.isRunning) {
        state = state.copyWith(
          statuses: Map<String, EngineRunStatus>.unmodifiable(
            _runner?.statuses ?? state.statuses,
          ),
          isRunning: false,
          runFinishedAt: DateTime.now(),
        );
      }
      rethrow;
    } finally {
      _claimed = false;
    }
  }

  /// The telemetry sink, resolved **per event** rather than cached in
  /// [build].
  ///
  /// It was cached so that a `record()` on a synchronous path — the
  /// engine-outcome callback fires from inside the runner — never touched
  /// `ref` after a disposal. The `ref.mounted` guard covers that case directly.
  /// What caching cost is why it is gone: `telemetryServiceProvider` is not
  /// constant for the life of a session. The consent store publishes `unset`
  /// synchronously and reads the persisted value back asynchronously, so at
  /// the moment this notifier builds — a cold start — the gate has not seen
  /// the user's stored answer yet and resolves the no-op. Holding that froze
  /// the first frame's verdict for the whole session. The call sites below
  /// stay unconditional; the read is a map lookup and the no-op's `record` is
  /// still allocation-free.
  void _record(String name, [Map<String, Object?>? properties]) {
    if (!ref.mounted) return;
    ref
        .read(telemetryServiceProvider)
        .record(TelemetryEvent(name, properties: properties));
  }

  /// Reports one engine's coarse outcome as `engine.run`.
  ///
  /// The engine id goes through [telemetryEngineToken] rather than being sent
  /// verbatim: `LintEngine.id` is a `String`, so an engine pack could put
  /// anything there, and the Worker would silently drop the property (leaving
  /// a healthy-looking counter with an empty dimension) rather than reject it.
  void _recordEngineOutcome(String engineId, EngineRunOutcome outcome) {
    _record('engine.run', <String, Object?>{
      'engine': telemetryEngineToken(engineId),
      'status': telemetryEnumToken(outcome),
    });
  }

  /// Reports one finished run as `run.completed`.
  ///
  /// Emitted from the notifier rather than from `LintRunCompletionDispatcher`,
  /// even though that seam's doc comment names telemetry as an intended
  /// subscriber: open core ships `NoopLintRunCompletionDispatcher`, and the
  /// real dispatcher is registered per tab by the Pro overlay. Instrumenting
  /// there would make two open-core counters Pro-only, which is the opposite
  /// of what they exist to measure.
  void _recordRunCompleted(LintRunTrigger trigger, int engines) {
    _record('run.completed', <String, Object?>{
      'trigger': telemetryEnumToken(trigger),
      'engines': engines,
    });
  }

  @override
  LintRunState build() {
    ref.onDispose(() {
      final sub = _statusSub;
      if (sub != null) {
        unawaited(sub.cancel());
      }
      _runner?.cancel();
      final runner = _runner;
      if (runner != null) {
        unawaited(runner.dispose());
      }
    });
    // Mirror every state change onto the services-layer lifecycle bus so
    // services-layer observers (e.g. the Pro trend dispatcher) can react
    // to run boundaries without importing this feature provider — the
    // `features → services` seam described in ARCHITECTURE.md §6.2.
    final lifecycle = ref.read(lintRunLifecycleBusProvider);
    listenSelf((_, next) {
      lifecycle.emit(
        LintRunLifecycleEvent(
          isRunning: next.isRunning,
          finishedAt: next.runFinishedAt,
        ),
      );
    });
    return LintRunState.idle;
  }

  /// Run every enabled engine in [project] concurrently. Violations
  /// from each engine land in the [ViolationStore] as soon as that
  /// engine finishes; the UI watches the store and re-renders
  /// progressively.
  ///
  /// [forceBypassCache]: when `true`, the lint-run
  /// cache is bypassed for this single invocation only — no
  /// lookups, no stores — regardless of [lintCacheEnabledProvider].
  /// Used by the `forceLintRunWithoutCache` action so users can
  /// re-run lint without trusting cached entries.
  ///
  /// [trigger] is the `run.completed` telemetry dimension — what started this
  /// run. It defaults to [LintRunTrigger.manual] because every UI entry point
  /// (the Run action, opening a project, restoring a tab) is user-initiated;
  /// the file watcher's incremental path is the one caller that passes
  /// [LintRunTrigger.auto], and it does so even when it falls back here from
  /// [runIncremental].
  Future<void> runAll(
    LintProject project, {
    bool forceBypassCache = false,
    LintRunTrigger trigger = LintRunTrigger.manual,
  }) => _asTheOnlyRun(
    () => _runAll(
      project,
      forceBypassCache: forceBypassCache,
      trigger: trigger,
    ),
  );

  Future<void> _runAll(
    LintProject project, {
    bool forceBypassCache = false,
    LintRunTrigger trigger = LintRunTrigger.manual,
  }) async {
    final pairs = _pairsFor(project);

    if (pairs.isEmpty) {
      // No engine ran, but custom-regex rules still scan source text.
      // Only pay the transformer/scan cost (and its async gaps) when the
      // project actually declares rules — this is a fire-and-forget call
      // (open-on-project), so guard every post-await state mutation with
      // `ref.mounted` in case the tab closed mid-scan.
      //
      // The `isRunning: true` transition is NOT optional on this path.
      // It is the lifecycle-bus edge every run-completion observer keys
      // on; without it a project whose violations come only from
      // custom-regex rules completes real runs that trend tracking,
      // bookmark stale-detection, and Verible auto-run never see.
      final startedAt = DateTime.now();
      state = state.copyWith(isRunning: true, runStartedAt: startedAt);
      if (project.customRegexRules.isNotEmpty) {
        final transformer = await _buildTransformer(project);
        if (!ref.mounted) return;
        await _evaluateCustomRules(project, transformer);
        if (!ref.mounted) return;
      }
      state = LintRunState.idle.copyWith(
        runStartedAt: startedAt,
        runFinishedAt: DateTime.now(),
      );
      // A real completed run with zero engines — custom-regex rules only.
      // Counting it keeps `engines` an honest distribution rather than one
      // that silently starts at 1.
      _recordRunCompleted(trigger, 0);
      return;
    }

    final transformer = await _buildTransformer(project);
    if (!ref.mounted) return;
    final runner = await _prepareRunner(
      project,
      pairs,
      transformer,
      forceBypassCache: forceBypassCache,
    );
    if (!ref.mounted) return;
    _statusSub = runner.statusEvents.listen(_onStatus);
    await runner.runAll(pairs);
    if (!ref.mounted) return;

    // Custom-regex rules. Evaluated after the engines so their
    // matches land in the store BEFORE the completion state transition
    // (which fires the lifecycle bus consumed by trend ingest etc.).
    // Open-core's NoopCustomRuleEvaluator makes this a no-op; the Pro
    // overlay's ProCustomRuleEvaluator produces the actual violations.
    // `_evaluateCustomRules` is synchronous (no await) when the project
    // has no rules, so this adds no gap on the common path.
    await _evaluateCustomRules(project, transformer);
    if (!ref.mounted) return;

    state = state.copyWith(
      statuses: Map<String, EngineRunStatus>.unmodifiable(runner.statuses),
      isRunning: false,
      runFinishedAt: DateTime.now(),
    );
    _recordRunCompleted(trigger, pairs.length);
  }

  /// Incremental re-run path. Called from the file watcher
  /// when one or more source files in the active project change.
  /// [changedFiles] is the absolute path set the watcher coalesced
  /// during the debounce window.
  ///
  /// Routing rules:
  ///   - If any enabled engine for the project does NOT declare
  ///     [EngineCapabilities.supportsIncrementalPerFile], the call
  ///     transparently falls back to [runAll] — we can't honor the
  ///     incremental contract for engines that need whole-project
  ///     elaboration.
  ///   - Otherwise each engine receives only the changed files that
  ///     intersect its routed source list; its previous violations on
  ///     those files are dropped via [ViolationStore.replacePartialFromEngine]
  ///     and the new set is added. Existing violations on unchanged
  ///     files (and from other engines) survive intact.
  ///   - Waivers, severity overrides, and saved filter presets are
  ///     unaffected — the transformer pipeline is the same.
  ///   - If the route would produce zero pairs (e.g. only `.vhd`
  ///     files changed and Verilator is the only enabled engine), the
  ///     call is a no-op.
  Future<void> runIncremental(
    LintProject project,
    Set<String> changedFiles,
  ) async {
    if (changedFiles.isEmpty) return;
    await _asTheOnlyRun(() => _runIncremental(project, changedFiles));
  }

  Future<void> _runIncremental(
    LintProject project,
    Set<String> changedFiles,
  ) async {
    final pairs = _pairsFor(project);
    if (pairs.isEmpty) {
      state = LintRunState.idle.copyWith(
        runStartedAt: DateTime.now(),
        runFinishedAt: DateTime.now(),
      );
      return;
    }

    // Fallback to full run when any enabled engine lacks incremental
    // support — the partial path would leave that engine's view stale.
    final allIncremental = pairs.every(
      (p) => p.engine.capabilities.supportsIncrementalPerFile,
    );
    if (!allIncremental) {
      // Still a watcher-driven run, so it keeps the `auto` trigger — the
      // fallback is an implementation detail of routing, not a different
      // thing the user did.
      await _runAll(project, trigger: LintRunTrigger.auto);
      return;
    }

    // Drop engines whose routed source list doesn't intersect the
    // changed file set — saves a noisy "0 violations" status flash
    // for engines that have nothing to look at.
    final scoped = <EngineRunPair>[
      for (final p in pairs)
        if (p.request.sourceFiles.any(changedFiles.contains)) p,
    ];
    if (scoped.isEmpty) return;

    final transformer = await _buildTransformer(project);
    if (!ref.mounted) return;
    final runner = await _prepareRunner(project, scoped, transformer);
    if (!ref.mounted) return;
    _statusSub = runner.statusEvents.listen(_onStatus);
    await runner.runIncremental(scoped, changedFiles);
    if (!ref.mounted) return;

    // Re-evaluate custom-regex rules against the (possibly changed)
    // source set. The evaluator re-scans every matching file and the
    // custom slice is wholesale-replaced, so an incremental engine run
    // keeps custom rules consistent without a per-file diff.
    await _evaluateCustomRules(project, transformer);
    if (!ref.mounted) return;

    state = state.copyWith(
      statuses: Map<String, EngineRunStatus>.unmodifiable(runner.statuses),
      isRunning: false,
      runFinishedAt: DateTime.now(),
    );
    _recordRunCompleted(LintRunTrigger.auto, scoped.length);
  }

  /// Builds the composite violation transformer for a run over [project]:
  /// severity overrides → source pragmas → managed waivers. Shared by the
  /// engine runner (applied to every streamed violation) and the
  /// custom-regex evaluation step (applied to each custom match) so custom
  /// rules are as waivable / severity-overridable as engine violations.
  Future<ViolationTransformer> _buildTransformer(LintProject project) async {
    // Read source-embedded `// verilator lint_off RULE` blocks so the
    // pragma waiver transformer can mark covered violations suppressed.
    const pragmaReader = PragmaWaiverReader();
    final rangeMap = await pragmaReader.readFiles(project.sourceFiles);
    // Managed waiver matcher: open-core's NoopWaiverStore makes this a
    // no-op; the Pro overlay's JsonFileWaiverStore (registered through
    // `waiverStoreProvider`) supplies the persistent matching engine.
    // Source pragmas are evaluated first so they always win — see
    // ManagedWaiverTransformer.transform's already-suppressed guard.
    final waiverStore = ref.read(waiverStoreProvider);
    return CompositeViolationTransformer([
      SeverityOverrideTransformer(project.severityOverrides),
      PragmaWaiverTransformer(rangeMap),
      ManagedWaiverTransformer(waiverStore),
    ]);
  }

  /// Evaluates the active [CustomRuleEvaluator] (open-core Noop by
  /// default; the Pro overlay's ProCustomRuleEvaluator) over the
  /// project's `customRegexRules` and stores the matches under the
  /// synthetic [kCustomRuleEngineId] slice — the same way an engine's
  /// output lands in the store — after passing each through [transformer]
  /// so custom violations honor waivers / severity overrides. When the
  /// project declares no rules, any prior custom slice is cleared so a
  /// rules removal is reflected on the next run.
  Future<void> _evaluateCustomRules(
    LintProject project,
    ViolationTransformer transformer,
  ) async {
    final store = ref.read(violationStoreProvider);
    final rules = project.customRegexRules;
    if (rules.isEmpty) {
      if (store.byEngineOf(kCustomRuleEngineId).isNotEmpty) {
        store
          ..replaceFromEngine(kCustomRuleEngineId, const [])
          ..completeStreaming(kCustomRuleEngineId);
      }
      return;
    }
    final evaluator = ref.read(customRuleEvaluatorProvider);
    final raw = await evaluator.evaluate(
      CustomRuleEvaluationContext(
        project: project,
        rules: rules,
        readFile: _readSourceFile,
      ),
    );
    final transformed = [for (final v in raw) transformer.transform(v)];
    store
      ..replaceFromEngine(kCustomRuleEngineId, transformed)
      ..completeStreaming(kCustomRuleEngineId);
  }

  /// Reads a source file as UTF-8, returning `null` on any I/O error so
  /// the evaluator skips missing / unreadable files without crashing the
  /// run (the [CustomRuleEvaluationContext.readFile] contract).
  Future<String?> _readSourceFile(String absolutePath) async {
    try {
      return await File(absolutePath).readAsString();
    } on Object {
      return null;
    }
  }

  Future<ParallelEngineRunner> _prepareRunner(
    LintProject project,
    List<EngineRunPair> pairs,
    ViolationTransformer transformer, {
    bool forceBypassCache = false,
  }) async {
    final store = ref.read(violationStoreProvider);

    // Tear down any prior runner before starting a fresh one. The old
    // runner's status stream is closed during disposal.
    await _statusSub?.cancel();
    await _runner?.dispose();

    // Cache wiring. Open-core ships NoopLintRunCacheService so the runner
    // integration is unconditional; the Pro overlay swaps in
    // SqliteLintRunCacheService via the overrides list. The settings-driven
    // `lintCacheEnabledProvider` lets users temporarily disable caching without
    // unloading the override.
    final cache = ref.read(lintRunCacheServiceProvider);
    final cacheEnabled = ref.read(lintCacheEnabledProvider);
    final runner = ParallelEngineRunner(
      store,
      transformer: transformer,
      cache: cache,
      cacheEnabled: cacheEnabled,
      forceBypassCache: forceBypassCache,
      watchdog: ref.read(engineWatchdogProvider),
      engineTimeout: ref.read(engineTimeoutProvider),
      onOutcome: _recordEngineOutcome,
    );
    _runner = runner;

    state = LintRunState(
      statuses: {
        for (final p in pairs) p.engine.id: EngineRunStatus.idle(p.engine.id),
      },
      isRunning: true,
      runStartedAt: DateTime.now(),
    );
    return runner;
  }

  List<EngineRunPair> _pairsFor(LintProject project) {
    final registry = ref.read(engineRegistryProvider);
    final settings = ref.read(appSettingsProvider);
    final cliArgs = ref.read(cliArgsProvider);
    return _pairsForProject(project, registry, settings, cliArgs);
  }

  /// Cancel the in-flight run. No-op when nothing is running.
  void cancel() {
    _runner?.cancel();
  }

  /// Convenience: current status of [engineId], or `null` if it was
  /// not part of the most recent run.
  EngineRunStatus? runStatusFor(String engineId) => state.statusFor(engineId);

  void _onStatus(EngineRunStatus status) {
    final next = Map<String, EngineRunStatus>.from(state.statuses);
    next[status.engineId] = status;
    state = state.copyWith(
      statuses: Map<String, EngineRunStatus>.unmodifiable(next),
    );
  }

  /// Produces one [EngineRunPair] per enabled engine after
  /// running every project source file through the
  /// [EngineLanguageRouter].
  ///
  /// Routing rules:
  ///   - Engines listed in `enabledEngineIds` (or every registered
  ///     engine when that list is empty) are candidates.
  ///   - Each engine receives only the project source files whose
  ///     effective language ([ProjectSourceFile.resolveLanguage]) is
  ///     in its [EngineCapabilities.supportedLanguages].
  ///   - Engines with zero compatible sources are dropped entirely —
  ///     the run-status panel still sees the empty case via the
  ///     `EngineLanguageRouting.perEngine` map (kept on the notifier
  ///     so the indicator can surface "ran against 0 of N sources"
  ///     even when no run started).
  ///   - The request's `language` is the engine's single supported
  ///     language when it only declares one (GHDL → vhdl, Verilator →
  ///     systemVerilog); otherwise the project-level declaration.
  List<EngineRunPair> _pairsForProject(
    LintProject project,
    EngineRegistry registry,
    AppSettings settings,
    CliArgs cliArgs,
  ) {
    // The planning itself lives in the Flutter-free
    // `EngineRunPlanner` so the headless CI binary
    // (`bin/lintcrux.dart`) routes sources to engines exactly the way
    // this notifier does — a CI gate that disagreed with the desktop
    // app about which engines saw which files would report a different
    // violation count for the same project.
    //
    // What stays here is the part that genuinely needs the widget-layer
    // context: resolving each engine's binary from Settings → Engines,
    // shadowed by any `--<engine>-path` CLI override for this run only.
    const planner = EngineRunPlanner();
    final plan = planner.plan(
      project: project,
      registry: registry,
      topModuleOverride: cliArgs.topModule,
      binaryConfigFor: (engineId) {
        final cliPath = cliArgs.engineBinaryPaths[engineId];
        if (cliPath != null && cliPath.isNotEmpty) {
          return EngineBinaryConfig(
            source: EngineBinarySource.custom,
            path: cliPath,
          );
        }
        return settings
            .engineBinaryOverrideFor(engineId)
            .toEngineBinaryConfig();
      },
    );
    _latestRouting = plan.routing;
    return plan.pairs;
  }

  EngineLanguageRouting? _latestRouting;

  /// Most recent routing snapshot. `null` until the first `runAll`
  /// call. The UI uses this to render the "ran against N of M sources"
  /// indicator regardless of whether the engine actually ran.
  EngineLanguageRouting? get latestRouting => _latestRouting;
}

/// Riverpod provider exposing the [LintRunNotifier].
final NotifierProvider<LintRunNotifier, LintRunState> lintRunProvider =
    NotifierProvider<LintRunNotifier, LintRunState>(LintRunNotifier.new);
