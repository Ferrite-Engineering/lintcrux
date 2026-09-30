// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/interfaces/lint_run_cache_service.dart';
import 'package:lintcrux/domain/models/lint_cache_entry.dart';
import 'package:lintcrux/domain/models/lint_cache_invalidation_event.dart';
import 'package:lintcrux/domain/models/lint_cache_key.dart';
import 'package:lintcrux/domain/models/lint_cache_stats.dart';
import 'package:lintcrux/services/lint_cache/lint_cache_enabled_provider.dart';
import 'package:lintcrux/services/lint_cache/lint_cache_stats_provider.dart';
import 'package:lintcrux/services/lint_cache/lint_run_cache_service_provider.dart';

class _FakeCache implements LintRunCacheService {
  _FakeCache(this.stub);
  final LintCacheStats stub;

  @override
  Future<void> clearAll() async {}

  @override
  Future<void> invalidate(LintCacheInvalidationEvent event) async {}

  @override
  Stream<LintCacheInvalidationEvent> get invalidations =>
      const Stream<LintCacheInvalidationEvent>.empty();

  @override
  Future<LintCacheEntry?> lookup(LintCacheKey key) async => null;

  @override
  Future<LintCacheStats> stats() async => stub;

  @override
  Future<void> store(LintCacheEntry entry) async {}
}

void main() {
  group('lintRunCacheServiceProvider', () {
    test('default resolves to NoopLintRunCacheService', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final svc = container.read(lintRunCacheServiceProvider);
      expect(svc, isA<NoopLintRunCacheService>());
    });

    test('Pro-style override replaces the default', () {
      final fake = _FakeCache(LintCacheStats.empty);
      final container = ProviderContainer(
        overrides: [
          lintRunCacheServiceProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);
      final svc = container.read(lintRunCacheServiceProvider);
      expect(identical(svc, fake), isTrue);
    });
  });

  group('lintCacheEnabledProvider', () {
    test('defaults to true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(lintCacheEnabledProvider), isTrue);
    });

    test('can be overridden to false', () {
      final container = ProviderContainer(
        overrides: [
          lintCacheEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(lintCacheEnabledProvider), isFalse);
    });
  });

  group('lintCacheStatsProvider', () {
    test('resolves to active cache service stats', () async {
      const stats = LintCacheStats(
        entryCount: 7,
        approximateBytes: 1024,
        hitCount: 3,
        missCount: 2,
        invalidationCount: 0,
        oldestEntryAt: null,
        newestEntryAt: null,
        averageRunDurationMs: 100,
        estimatedTimeSavedMs: 300,
      );
      final container = ProviderContainer(
        overrides: [
          lintRunCacheServiceProvider.overrideWithValue(_FakeCache(stats)),
        ],
      );
      addTearDown(container.dispose);
      final s = await container.read(lintCacheStatsProvider.future);
      expect(s, equals(stats));
    });

    test('defaults to LintCacheStats.empty under the noop service', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final s = await container.read(lintCacheStatsProvider.future);
      expect(s, equals(LintCacheStats.empty));
    });
  });
}
