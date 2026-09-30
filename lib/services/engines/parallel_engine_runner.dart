// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:lintcrux/domain/interfaces/engine_watchdog.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/interfaces/lint_run_cache_service.dart';
import 'package:lintcrux/domain/interfaces/violation_store.dart';
import 'package:lintcrux/domain/interfaces/violation_transformer.dart';
import 'package:lintcrux/domain/models/engine_run_outcome.dart';
import 'package:lintcrux/domain/models/engine_run_status.dart';
import 'package:lintcrux/domain/models/lint_cache_entry.dart';
import 'package:lintcrux/domain/models/lint_cache_invalidation_event.dart';
import 'package:lintcrux/domain/models/lint_cache_key.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/timeout_engine_watchdog.dart';
import 'package:lintcrux/services/lint_cache/cache_fingerprint.dart';

/// Orchestrates the parallel execution of multiple [LintEngine]s
/// against a project.
///
/// Each (engine, request) pair runs concurrently. As each engine
/// completes, its violations replace the previous violations for that
/// engine in the [ViolationStore] via
/// [ViolationStore.replaceFromEngine] — so progressive UI updates
/// happen the moment any engine finishes, without waiting for the
/// slow ones.
///
/// [statusEvents] streams per-engine [EngineRunStatus] transitions so
/// the UI can render spinners, error chips, and "no violations found"
/// placeholders without polling. The stream closes when the run
/// finishes (every engine reached a terminal phase).
///
/// [cancel] propagates a cancel to every active engine and finalizes
/// any not-yet-terminal status to [EngineRunPhase.cancelled].
class ParallelEngineRunner {
  /// Creates a [ParallelEngineRunner] over [store]. The optional
  /// [transformer] is applied to every violation before it reaches
  /// the store — used for per-rule severity overrides and
  /// inline-pragma waiver matching. Defaults to a no-op composite.
  ///
  /// [cache] is the lint-run cache surface. Defaults
  /// to [NoopLintRunCacheService] so the open-core build behaves
  /// exactly like the pre-cache code path; the Pro overlay injects
  /// the SQLite-backed `SqliteLintRunCacheService`. When [cacheEnabled]
  /// is `false`, the runner bypasses the cache regardless of which
  /// implementation is wired up.
  ///
  /// [forceBypassCache] is a one-shot flag set by the
  /// `forceLintRunWithoutCache` action: lookups skipped and stores
  /// skipped for the *single* run constructed with the flag set,
  /// after which the caller discards the runner.
  ///
  /// [onOutcome] is the `engine.run` telemetry seam: one call per engine that
  /// reached a *non-cancelled* terminal state, carrying the coarse
  /// [EngineRunOutcome] rather than the display-oriented [EngineRunPhase].
  /// It exists because the phase alone cannot answer "is this engine healthy
  /// in the field" — a watchdog kill and a crashed subprocess are both
  /// `failed`, and they are different answers. Both surfaces pass it: the
  /// desktop app routes it to `telemetryServiceProvider`, the headless binary
  /// to its own reporter, so a CI run and a desktop run count the same way.
  ParallelEngineRunner(
    this.store, {
    this.transformer = CompositeViolationTransformer.empty,
    this.cache = const NoopLintRunCacheService(),
    this.cacheEnabled = true,
    this.forceBypassCache = false,
    this.watchdog = const TimeoutEngineWatchdog(),
    this.engineTimeout = const Duration(seconds: 120),
    this.onOutcome,
  });

  /// The violation store mutated on engine completion.
  final ViolationStore store;

  /// Called once per engine that reached a non-cancelled terminal state.
  ///
  /// Never awaited and never allowed to affect the run: the callers wrap the
  /// body themselves, because a telemetry sink that threw here would take a
  /// lint run down with it.
  final void Function(String engineId, EngineRunOutcome outcome)? onOutcome;

  /// Bounds the wall-clock time any single engine run may take.
  /// A hung engine is killed once [engineTimeout]
  /// elapses with no output; the run completes for the other engines.
  /// Defaults to the active [TimeoutEngineWatchdog]; production wires the
  /// `engineWatchdogProvider`.
  final EngineWatchdog watchdog;

  /// The per-engine wall-clock budget the [watchdog] enforces. Defaults
  /// to 120 s; production wires `engineTimeoutProvider` (Settings-driven).
  final Duration engineTimeout;

  /// Transform applied to every violation before storage.
  final ViolationTransformer transformer;

  /// Lint-run cache. Defaults to no-op.
  final LintRunCacheService cache;

  /// Whether the cache should be consulted at all. Settings-driven.
  final bool cacheEnabled;

  /// One-shot per-runner-instance override used by the
  /// `forceLintRunWithoutCache` action: caches are bypassed for
  /// every engine in this run.
  final bool forceBypassCache;

  /// Engine ids whose result was served from cache in the most
  /// recent run. Exposed for the lint-run completion event so
  /// downstream consumers (trend ingest, diagnostics) can
  /// distinguish a cached run from a fresh one.
  Set<String> get cachedEngineIds => Set<String>.unmodifiable(_cachedEngineIds);
  final Set<String> _cachedEngineIds = <String>{};

  bool get _cacheActive => cacheEnabled && !forceBypassCache;

  final Map<String, EngineRunStatus> _statuses = <String, EngineRunStatus>{};
  final List<LintEngine> _active = <LintEngine>[];
  final StreamController<EngineRunStatus> _statusCtrl =
      StreamController<EngineRunStatus>.broadcast();
  bool _cancelled = false;

  /// Live stream of per-engine status transitions.
  Stream<EngineRunStatus> get statusEvents => _statusCtrl.stream;

  /// Current snapshot of every engine's status, keyed by engine id.
  Map<String, EngineRunStatus> get statuses =>
      Map<String, EngineRunStatus>.unmodifiable(_statuses);

  /// Status for [engineId], or null if [engineId] was not part of this
  /// run.
  EngineRunStatus? statusFor(String engineId) => _statuses[engineId];

  /// Whether any engine is currently in a non-terminal phase.
  bool get isRunning => _statuses.values.any((s) => !s.isTerminal);

  /// Run every [pairs] engine concurrently. Returns when every engine
  /// has reached a terminal phase. Throws nothing — engine failures
  /// surface as [EngineRunPhase.failed] or [EngineRunPhase.unavailable]
  /// statuses, not exceptions.
  Future<void> runAll(List<EngineRunPair> pairs) async {
    _cancelled = false;
    _cachedEngineIds.clear();
    _statuses
      ..clear()
      ..addEntries(
        pairs.map(
          (p) => MapEntry(
            p.engine.id,
            EngineRunStatus.idle(p.engine.id).copyWith(
              sourcesUsed: p.sourcesUsed,
              sourcesTotal: p.sourcesTotal,
            ),
          ),
        ),
      );
    _active
      ..clear()
      ..addAll(pairs.map((p) => p.engine));

    final futures = pairs.map(_runOne).toList(growable: false);
    await Future.wait<void>(futures);
  }

  /// Incremental re-run path. Each engine sees only the
  /// changed files (intersected with its routed source list), and the
  /// per-engine violation set is patched into the store via
  /// [ViolationStore.replacePartialFromEngine] — existing violations
  /// on unchanged files survive intact.
  ///
  /// Pre-condition: every pair's engine declares
  /// [EngineCapabilities.supportsIncrementalPerFile]. The caller
  /// ([LintRunNotifier]) enforces this; engines that can't go
  /// incremental fall back to a full [runAll] at the orchestration
  /// layer.
  ///
  /// Status semantics match [runAll] — same phases, same stream,
  /// same cancellation contract.
  Future<void> runIncremental(
    List<EngineRunPair> pairs,
    Set<String> changedFiles,
  ) async {
    _cancelled = false;
    _cachedEngineIds.clear();
    _statuses
      ..clear()
      ..addEntries(
        pairs.map(
          (p) => MapEntry(
            p.engine.id,
            EngineRunStatus.idle(p.engine.id).copyWith(
              sourcesUsed: p.sourcesUsed,
              sourcesTotal: p.sourcesTotal,
            ),
          ),
        ),
      );
    _active
      ..clear()
      ..addAll(pairs.map((p) => p.engine));

    final futures = pairs
        .map((p) => _runOneIncremental(p, changedFiles))
        .toList(growable: false);
    await Future.wait<void>(futures);
  }

  /// Shared prologue for both run paths. If a cancel is already latched,
  /// emits the terminal `cancelled` status and returns `null` so the caller
  /// short-circuits; otherwise returns the run start timestamp.
  DateTime? _beginRun(EngineRunPair pair) {
    if (_cancelled) {
      _emitPhase(pair, EngineRunPhase.cancelled);
      return null;
    }
    return DateTime.now();
  }

  /// Drives [stream] (an engine's violation stream) through the watchdog,
  /// emitting live `running` progress and transforming each violation. This
  /// is the scaffold [_runOne] and [_runOneIncremental] share — only the
  /// stream source and the store-mutation policy differ between them.
  ///
  /// Terminal semantics:
  ///  - the three engine exceptions (`EngineTimedOutException`,
  ///    `EngineNotAvailableException`, any other) each emit the matching
  ///    terminal status and yield [_DrainOutcome.errored];
  ///  - a mid-drain cancel emits `cancelled` and yields
  ///    [_DrainOutcome.cancelled];
  ///  - a clean drain yields [_DrainOutcome.completed] *without* emitting the
  ///    `completed` status — the caller owns that emit plus the store
  ///    mutation, which differ between the full and incremental paths.
  ///
  /// When [rawSink] is supplied, each pre-transformer violation is appended
  /// to it — the full-run cache path needs the raw output; the incremental
  /// path passes `null`.
  Future<_EngineDrainResult> _drainEngine(
    EngineRunPair pair,
    Stream<Violation> stream,
    DateTime startedAt, {
    List<Violation>? rawSink,
  }) async {
    final engine = pair.engine;
    final collected = <Violation>[];
    try {
      final guarded = watchdog.guard<Violation>(
        stream,
        timeout: engineTimeout,
        engineId: engine.id,
        onTimeout: engine.cancel,
      );
      await for (final v in guarded) {
        if (_cancelled) break;
        rawSink?.add(v);
        collected.add(transformer.transform(v));
        _emitPhase(
          pair,
          EngineRunPhase.running,
          violationCount: collected.length,
          startedAt: startedAt,
        );
      }
    } on EngineTimedOutException catch (e) {
      _emitPhase(
        pair,
        EngineRunPhase.failed,
        error: e.toString(),
        startedAt: startedAt,
        completedAt: DateTime.now(),
        outcome: EngineRunOutcome.timeout,
      );
      return _EngineDrainResult(collected, _DrainOutcome.errored);
    } on EngineNotAvailableException catch (e) {
      _emitPhase(
        pair,
        EngineRunPhase.unavailable,
        error: e.reason,
        startedAt: startedAt,
        completedAt: DateTime.now(),
        outcome: EngineRunOutcome.missing,
      );
      return _EngineDrainResult(collected, _DrainOutcome.errored);
    } on Object catch (e) {
      _emitPhase(
        pair,
        EngineRunPhase.failed,
        error: e.toString(),
        startedAt: startedAt,
        completedAt: DateTime.now(),
        outcome: EngineRunOutcome.crash,
      );
      return _EngineDrainResult(collected, _DrainOutcome.errored);
    }

    if (_cancelled) {
      _emitPhase(
        pair,
        EngineRunPhase.cancelled,
        violationCount: collected.length,
        startedAt: startedAt,
        completedAt: DateTime.now(),
      );
      return _EngineDrainResult(collected, _DrainOutcome.cancelled);
    }

    return _EngineDrainResult(collected, _DrainOutcome.completed);
  }

  Future<void> _runOne(EngineRunPair pair) async {
    final engine = pair.engine;
    final request = pair.request;
    final startedAt = _beginRun(pair);
    if (startedAt == null) return;

    // ── Cache lookup ──────────────────────────────
    // Compute the cache key and try a hit *before* announcing that
    // the engine is running. On hit we synthesize a single
    // `completed` status with `violationCount` set to the cached
    // result's length, apply the transformer pipeline to the cached
    // violations, and store them — no engine subprocess invocation.
    //
    // A `null` cache key (binary path unresolved, source file
    // unreadable, engine version unknown) skips the lookup and
    // proceeds to the engine invocation; the engine itself will
    // surface any underlying I/O failure through its normal error
    // reporting path.
    final cacheKey = _cacheActive && engine.capabilities.cacheable
        ? await _buildCacheKey(engine: engine, request: request)
        : null;
    if (cacheKey != null) {
      // Advisory, like the store below: a cache that cannot answer (a full
      // disk, a busy or damaged database) is a miss, and the engine runs.
      // Unguarded, the throw ended the whole run and left the tab's run
      // state "running" for the rest of its life.
      LintCacheEntry? hit;
      try {
        hit = await cache.lookup(cacheKey);
      } on Object {
        hit = null;
      }
      if (hit != null) {
        _cachedEngineIds.add(engine.id);
        final transformed = [
          for (final v in hit.violations) transformer.transform(v),
        ];
        store
          ..replaceFromEngine(engine.id, transformed)
          ..completeStreaming(engine.id);
        _emitPhase(
          pair,
          EngineRunPhase.completed,
          violationCount: transformed.length,
          startedAt: startedAt,
          completedAt: DateTime.now(),
          outcome: EngineRunOutcome.ok,
        );
        return;
      }
    }

    _emitPhase(pair, EngineRunPhase.running, startedAt: startedAt);

    // Capture the pre-transformer violations for the cache store below.
    final rawForCache = <Violation>[];
    final result = await _drainEngine(
      pair,
      engine.run(request),
      startedAt,
      rawSink: rawForCache,
    );
    switch (result.outcome) {
      case _DrainOutcome.errored:
        // The failure status is already emitted; clear the engine's set.
        store.replaceFromEngine(engine.id, const []);
        return;
      case _DrainOutcome.cancelled:
        // Even on cancel, flush whatever the engine produced.
        store.replaceFromEngine(engine.id, result.collected);
        return;
      case _DrainOutcome.completed:
        break;
    }

    final completedAt = DateTime.now();
    store
      ..replaceFromEngine(engine.id, result.collected)
      ..completeStreaming(engine.id);
    _emitPhase(
      pair,
      EngineRunPhase.completed,
      violationCount: result.collected.length,
      startedAt: startedAt,
      completedAt: completedAt,
      outcome: EngineRunOutcome.ok,
    );

    // ── Cache store ───────────────────────────────
    // Store the pre-transformer violations so future cache hits
    // re-apply the transformer pipeline against the engine's raw
    // output. This keeps waivers / severity overrides / pragmas
    // honored on every hit — changing them at runtime doesn't
    // invalidate the cache, the hit just re-runs the transformer
    // chain against the cached raw set.
    if (cacheKey != null && !_cancelled) {
      try {
        final runDurationMs = completedAt.difference(startedAt).inMilliseconds;
        final entry = LintCacheEntry(
          key: cacheKey,
          violations: rawForCache,
          createdAt: completedAt,
          lastAccessedAt: completedAt,
          runDurationMs: runDurationMs,
          // Use the request's first source file as the entry's
          // file_path label — file-changed invalidation works
          // against this field. When the runner is invoked with
          // multiple files (whole-project run), the cache treats
          // them as one entry keyed by the joint source
          // fingerprint; any file change rebuilds the joint
          // fingerprint and produces a miss.
          filePath: request.sourceFiles.isEmpty
              ? ''
              : request.sourceFiles.first,
        );
        await cache.store(entry);
      } on Object {
        // Cache store failures are advisory — log and continue.
      }
    }
  }

  /// Builds the [LintCacheKey] for [engine] + [request]. Returns
  /// `null` when any required fingerprint cannot be computed —
  /// missing source files, unresolved engine binary, or a
  /// `detectVersion` call that returns null. A `null` key bypasses
  /// the cache for this invocation; the engine runs normally.
  Future<LintCacheKey?> _buildCacheKey({
    required LintEngine engine,
    required LintRunRequest request,
  }) async {
    if (request.sourceFiles.isEmpty) return null;
    // Combine every source file's fingerprint into one composite
    // hash. Order-preserving — engines that depend on file order
    // see ordered hashes; engines that are order-independent
    // still benefit because the runner's pair construction is
    // deterministic.
    final combined = StringBuffer();
    for (final path in request.sourceFiles) {
      final hash = await CacheFingerprint.sourceOf(path);
      if (hash == null) return null;
      combined
        ..write(hash)
        ..write('\n');
    }
    final sourceFp = CacheFingerprint.sourceOfBytes(
      combined.toString().codeUnits,
    );
    final configFp = CacheFingerprint.configOf(request, engineId: engine.id);
    String? version;
    try {
      version = await engine.detectVersion(request.binary);
    } on Object {
      version = null;
    }
    if (version == null || version.isEmpty) return null;
    return LintCacheKey(
      engineId: engine.id,
      sourceFingerprint: sourceFp,
      configFingerprint: configFp,
      engineVersion: version,
    );
  }

  /// Not wired into the run path: invalidation is driven from the
  /// file-watcher / config-change listeners directly via
  /// [LintRunCacheService.invalidate]. Kept as a helper so the runner
  /// integration point stays in one place should invalidations ever need
  /// to route through here for logging.
  // ignore: unused_element
  Future<void> _invalidate(LintCacheInvalidationEvent event) =>
      cache.invalidate(event);

  /// Incremental variant of [_runOne] — invokes
  /// [LintEngine.runIncremental] and patches the engine's set in the
  /// store via [ViolationStore.replacePartialFromEngine] instead of
  /// wholesale replacement.
  Future<void> _runOneIncremental(
    EngineRunPair pair,
    Set<String> changedFiles,
  ) async {
    final engine = pair.engine;
    final request = pair.request;
    final startedAt = _beginRun(pair);
    if (startedAt == null) return;

    _emitPhase(pair, EngineRunPhase.running, startedAt: startedAt);

    final result = await _drainEngine(
      pair,
      engine.runIncremental(request, changedFiles),
      startedAt,
    );
    switch (result.outcome) {
      case _DrainOutcome.errored:
        // No partial mutation — leave the prior engine set intact so the
        // user sees the pre-incremental state on failure.
        return;
      case _DrainOutcome.cancelled:
        store.replacePartialFromEngine(
          engine.id,
          changedFiles,
          result.collected,
        );
        return;
      case _DrainOutcome.completed:
        break;
    }

    store
      ..replacePartialFromEngine(engine.id, changedFiles, result.collected)
      ..completeStreaming(engine.id);
    _emitPhase(
      pair,
      EngineRunPhase.completed,
      violationCount: result.collected.length,
      startedAt: startedAt,
      completedAt: DateTime.now(),
      outcome: EngineRunOutcome.ok,
    );
  }

  /// Cancel every active engine. Idempotent.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final engine in _active) {
      engine.cancel();
    }
  }

  /// Disposes the status stream.
  Future<void> dispose() async {
    await _statusCtrl.close();
  }

  void _emit(EngineRunStatus status) {
    _statuses[status.engineId] = status;
    if (!_statusCtrl.isClosed) {
      _statusCtrl.add(status);
    }
  }

  /// Builds and emits an [EngineRunStatus] for [pair] in [phase], threading
  /// the pair's `sourcesUsed` / `sourcesTotal`. Collapses the many
  /// near-identical status constructions the two run paths shared;
  /// `violationCount` defaults to `0` to match [EngineRunStatus]'s own
  /// default for the pre-progress phases (`cancelled` / initial `running`).
  ///
  /// [outcome] is the coarse [EngineRunOutcome] this transition also reports
  /// to [onOutcome], if any. It is a parameter of *this* method rather than a
  /// separate call at each site so the two can never disagree about which
  /// transitions are terminal — the `running` progress ticks pass `null` and
  /// report nothing, and a cancelled engine passes `null` on purpose (see
  /// [EngineRunOutcome]).
  void _emitPhase(
    EngineRunPair pair,
    EngineRunPhase phase, {
    int violationCount = 0,
    String? error,
    DateTime? startedAt,
    DateTime? completedAt,
    EngineRunOutcome? outcome,
  }) {
    _emit(
      EngineRunStatus(
        engineId: pair.engine.id,
        phase: phase,
        violationCount: violationCount,
        error: error,
        startedAt: startedAt,
        completedAt: completedAt,
        sourcesUsed: pair.sourcesUsed,
        sourcesTotal: pair.sourcesTotal,
      ),
    );
    if (outcome == null) return;
    try {
      onOutcome?.call(pair.engine.id, outcome);
    } on Object catch (_) {
      // A counter is never worth a failed lint run. `crux_telemetry`'s own
      // sink already swallows; this guard covers whatever else a caller
      // eventually binds here.
    }
  }
}

/// How an engine's stream drain terminated — see
/// [ParallelEngineRunner._drainEngine].
enum _DrainOutcome {
  /// Stream drained cleanly to completion.
  completed,

  /// A cancel was latched mid-drain.
  cancelled,

  /// The engine threw one of the terminal exceptions.
  errored,
}

/// Result of draining one engine's violation stream: the transformed
/// violations collected before termination, plus how the drain ended. The
/// terminal status is already emitted by [ParallelEngineRunner._drainEngine]
/// for the `cancelled` / `errored` outcomes; the caller owns the `completed`
/// emit and the store mutation.
class _EngineDrainResult {
  const _EngineDrainResult(this.collected, this.outcome);

  /// Transformed violations collected before the drain terminated.
  final List<Violation> collected;

  /// How the drain terminated.
  final _DrainOutcome outcome;
}

/// One (engine, request) pair for [ParallelEngineRunner.runAll].
class EngineRunPair {
  /// Creates an [EngineRunPair].
  const EngineRunPair({
    required this.engine,
    required this.request,
    this.sourcesUsed,
    this.sourcesTotal,
  });

  /// Engine to invoke.
  final LintEngine engine;

  /// Request the engine receives.
  final LintRunRequest request;

  /// Number of project source files this engine received
  /// after language routing. `null` when routing did not apply (the
  /// engine got every project source file, the historical pre-Phase-2
  /// behaviour). Threaded through every [EngineRunStatus] the runner
  /// emits.
  final int? sourcesUsed;

  /// Total project source files at the time of this run.
  /// `null` when routing did not apply. Paired with [sourcesUsed].
  final int? sourcesTotal;
}
