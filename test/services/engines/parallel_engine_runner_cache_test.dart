// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/interfaces/lint_run_cache_service.dart';
import 'package:lintcrux/domain/interfaces/violation_transformer.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/lint_cache_entry.dart';
import 'package:lintcrux/domain/models/lint_cache_invalidation_event.dart';
import 'package:lintcrux/domain/models/lint_cache_key.dart';
import 'package:lintcrux/domain/models/lint_cache_stats.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/parallel_engine_runner.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';

/// In-memory cache that records every interaction so tests can
/// assert hit/miss/store behavior without a SQLite dependency.
class _MemoryCache implements LintRunCacheService {
  final Map<LintCacheKey, LintCacheEntry> _entries = {};
  int lookupCalls = 0;
  int storeCalls = 0;
  int hits = 0;
  int misses = 0;
  final StreamController<LintCacheInvalidationEvent> _ctrl =
      StreamController<LintCacheInvalidationEvent>.broadcast();

  @override
  Future<LintCacheEntry?> lookup(LintCacheKey key) async {
    lookupCalls++;
    final hit = _entries[key];
    if (hit != null) {
      hits++;
      return hit;
    }
    misses++;
    return null;
  }

  @override
  Future<void> store(LintCacheEntry entry) async {
    storeCalls++;
    _entries[entry.key] = entry;
  }

  @override
  Future<void> invalidate(LintCacheInvalidationEvent event) async {
    _ctrl.add(event);
  }

  @override
  Future<LintCacheStats> stats() async => LintCacheStats(
    entryCount: _entries.length,
    approximateBytes: 0,
    hitCount: hits,
    missCount: misses,
    invalidationCount: 0,
    oldestEntryAt: null,
    newestEntryAt: null,
    averageRunDurationMs: 0,
    estimatedTimeSavedMs: 0,
  );

  @override
  Future<void> clearAll() async {
    _entries.clear();
  }

  @override
  Stream<LintCacheInvalidationEvent> get invalidations => _ctrl.stream;

  Future<void> shutdown() => _ctrl.close();
}

/// A cache whose lookups fail, the way a database that is full, busy or
/// damaged does.
class _ThrowingLookupCache extends _MemoryCache {
  @override
  Future<LintCacheEntry?> lookup(LintCacheKey key) async =>
      throw StateError('database is locked');
}

class _CountingEngine implements LintEngine {
  _CountingEngine(this.id, this._violations);

  @override
  final String id;
  final List<Violation> _violations;
  int runCalls = 0;
  bool cancelled = false;

  @override
  String get displayName => 'Counting $id';

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.systemVerilog},
  );

  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async => '1.0.0';

  @override
  Stream<Violation> run(LintRunRequest request) async* {
    runCalls++;
    for (final v in _violations) {
      if (cancelled) return;
      yield v;
    }
  }

  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) => run(request);

  @override
  void cancel() {
    cancelled = true;
  }
}

class _UpgradeToError implements ViolationTransformer {
  @override
  Violation transform(Violation v) {
    if (v.severity == Severity.warning) {
      return v.copyWith(severity: Severity.error);
    }
    return v;
  }
}

void main() {
  late Directory tmp;
  late File sourceFile;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lintcrux_runner_cache');
    sourceFile = File('${tmp.path}/a.sv')
      ..writeAsStringSync('module a;\nendmodule\n');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  EngineRunPair pair({required LintEngine engine}) {
    return EngineRunPair(
      engine: engine,
      request: LintRunRequest(
        sourceFiles: [sourceFile.path],
        language: HdlLanguage.systemVerilog,
        binary: const EngineBinaryConfig(
          source: EngineBinarySource.system,
          path: '/usr/bin/something',
        ),
      ),
    );
  }

  Violation v() => Violation(
    engineId: 'fake',
    ruleId: 'fake/RULE_A',
    severity: Severity.warning,
    message: 'Sample',
    location: SourceLocation(file: sourceFile.path, line: 1, column: 1),
  );

  group('ParallelEngineRunner cache integration', () {
    test('cache miss: engine runs and result is stored', () async {
      final cache = _MemoryCache();
      addTearDown(cache.shutdown);
      final engine = _CountingEngine('fake', [v()]);
      final store = InMemoryViolationStore();
      final runner = ParallelEngineRunner(store, cache: cache);
      addTearDown(runner.dispose);

      await runner.runAll([pair(engine: engine)]);

      expect(engine.runCalls, equals(1));
      expect(cache.misses, equals(1));
      expect(cache.storeCalls, equals(1));
      expect(runner.cachedEngineIds, isEmpty);
      expect(store.all, hasLength(1));
    });

    test('a cache lookup that throws is a miss: the engine runs', () async {
      final cache = _ThrowingLookupCache();
      addTearDown(cache.shutdown);
      final engine = _CountingEngine('fake', [v()]);
      final store = InMemoryViolationStore();
      final runner = ParallelEngineRunner(store, cache: cache);
      addTearDown(runner.dispose);

      await runner.runAll([pair(engine: engine)]);

      expect(engine.runCalls, equals(1));
      expect(store.all, hasLength(1));
    });

    test('cache hit on second run: engine NOT invoked', () async {
      final cache = _MemoryCache();
      addTearDown(cache.shutdown);
      final engine = _CountingEngine('fake', [v()]);
      final store = InMemoryViolationStore();

      final r1 = ParallelEngineRunner(store, cache: cache);
      await r1.runAll([pair(engine: engine)]);
      await r1.dispose();

      // Re-run with a fresh runner.
      final store2 = InMemoryViolationStore();
      final r2 = ParallelEngineRunner(store2, cache: cache);
      addTearDown(r2.dispose);
      final engine2 = _CountingEngine('fake', [v()]);
      await r2.runAll([pair(engine: engine2)]);

      expect(engine.runCalls, equals(1));
      // Critical: engine2 was NOT invoked because the cache hit.
      expect(engine2.runCalls, equals(0));
      expect(cache.hits, equals(1));
      expect(r2.cachedEngineIds, equals({'fake'}));
      // Cached violations still landed in the store.
      expect(store2.all, hasLength(1));
    });

    test('cacheEnabled=false bypasses both lookup and store', () async {
      final cache = _MemoryCache();
      addTearDown(cache.shutdown);
      final engine = _CountingEngine('fake', [v()]);
      final store = InMemoryViolationStore();
      final runner = ParallelEngineRunner(
        store,
        cache: cache,
        cacheEnabled: false,
      );
      addTearDown(runner.dispose);

      await runner.runAll([pair(engine: engine)]);

      expect(engine.runCalls, equals(1));
      expect(cache.lookupCalls, equals(0));
      expect(cache.storeCalls, equals(0));
      expect(runner.cachedEngineIds, isEmpty);
    });

    test('forceBypassCache=true bypasses cache for one run', () async {
      final cache = _MemoryCache();
      addTearDown(cache.shutdown);
      final engine = _CountingEngine('fake', [v()]);
      final store = InMemoryViolationStore();

      // Prime the cache.
      final priming = ParallelEngineRunner(store, cache: cache);
      await priming.runAll([pair(engine: engine)]);
      await priming.dispose();
      expect(cache.storeCalls, equals(1));
      cache
        ..lookupCalls = 0
        ..storeCalls = 0;

      // Bypass run — should run the engine and NOT consult the cache.
      final engine2 = _CountingEngine('fake', [v()]);
      final bypass = ParallelEngineRunner(
        InMemoryViolationStore(),
        cache: cache,
        forceBypassCache: true,
      );
      addTearDown(bypass.dispose);
      await bypass.runAll([pair(engine: engine2)]);

      expect(engine2.runCalls, equals(1));
      expect(cache.lookupCalls, equals(0));
      expect(cache.storeCalls, equals(0));
      expect(bypass.cachedEngineIds, isEmpty);
    });

    test(
      'cache hit applies transformer pipeline to cached violations',
      () async {
        final cache = _MemoryCache();
        addTearDown(cache.shutdown);
        final engine = _CountingEngine('fake', [v()]);
        final store = InMemoryViolationStore();
        final priming = ParallelEngineRunner(store, cache: cache);
        await priming.runAll([pair(engine: engine)]);
        await priming.dispose();

        // Second run with a severity-bumping transformer; the cache
        // hit should still see the override applied because the
        // transformer pipeline runs on every emission (cached or fresh).
        final store2 = InMemoryViolationStore();
        final engine2 = _CountingEngine('fake', [v()]);
        final r2 = ParallelEngineRunner(
          store2,
          cache: cache,
          transformer: _UpgradeToError(),
        );
        addTearDown(r2.dispose);
        await r2.runAll([pair(engine: engine2)]);

        expect(engine2.runCalls, equals(0));
        expect(r2.cachedEngineIds, equals({'fake'}));
        expect(store2.all.single.severity, equals(Severity.error));
      },
    );

    test('runner clears cachedEngineIds at the start of every run', () async {
      final cache = _MemoryCache();
      addTearDown(cache.shutdown);
      final engine = _CountingEngine('fake', [v()]);
      final store = InMemoryViolationStore();
      final runner = ParallelEngineRunner(store, cache: cache);
      addTearDown(runner.dispose);

      // Run 1: miss.
      await runner.runAll([pair(engine: engine)]);
      expect(runner.cachedEngineIds, isEmpty);

      // Run 2: hit on the same runner instance.
      await runner.runAll([pair(engine: engine)]);
      expect(runner.cachedEngineIds, equals({'fake'}));

      // Run 3: invalidate cache, expect cachedEngineIds to clear.
      await cache.clearAll();
      final engine3 = _CountingEngine('fake', [v()]);
      await runner.runAll([pair(engine: engine3)]);
      expect(runner.cachedEngineIds, isEmpty);
    });

    test('runner falls back to engine when source fingerprint fails '
        '(file missing)', () async {
      final cache = _MemoryCache();
      addTearDown(cache.shutdown);
      final engine = _CountingEngine('fake', [v()]);
      final store = InMemoryViolationStore();
      final runner = ParallelEngineRunner(store, cache: cache);
      addTearDown(runner.dispose);

      // Delete the file BEFORE the run — fingerprint computation
      // returns null, the cache key cannot be built, the runner
      // proceeds straight to the engine with no lookup/store.
      sourceFile.deleteSync();
      await runner.runAll([pair(engine: engine)]);

      expect(engine.runCalls, equals(1));
      expect(cache.lookupCalls, equals(0));
      expect(cache.storeCalls, equals(0));
    });
  });
}
