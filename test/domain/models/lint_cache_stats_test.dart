// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/lint_cache_stats.dart';

void main() {
  group('LintCacheStats', () {
    test('empty constant is all zeros / nulls', () {
      const s = LintCacheStats.empty;
      expect(s.entryCount, equals(0));
      expect(s.approximateBytes, equals(0));
      expect(s.hitCount, equals(0));
      expect(s.missCount, equals(0));
      expect(s.invalidationCount, equals(0));
      expect(s.oldestEntryAt, isNull);
      expect(s.newestEntryAt, isNull);
      expect(s.averageRunDurationMs, equals(0));
      expect(s.estimatedTimeSavedMs, equals(0));
    });

    test('hitRate is 0 when there are no lookups', () {
      expect(LintCacheStats.empty.hitRate, equals(0));
    });

    test('hitRate computes hits / (hits + misses)', () {
      const s = LintCacheStats(
        entryCount: 5,
        approximateBytes: 1024,
        hitCount: 8,
        missCount: 2,
        invalidationCount: 1,
        oldestEntryAt: null,
        newestEntryAt: null,
        averageRunDurationMs: 1000,
        estimatedTimeSavedMs: 8000,
      );
      expect(s.hitRate, closeTo(0.8, 1e-9));
    });

    test('equality is structural across all fields', () {
      final a = DateTime.utc(2026, 5, 25);
      final b = DateTime.utc(2026, 5, 25, 1);
      final s1 = LintCacheStats(
        entryCount: 3,
        approximateBytes: 256,
        hitCount: 4,
        missCount: 6,
        invalidationCount: 2,
        oldestEntryAt: a,
        newestEntryAt: b,
        averageRunDurationMs: 100,
        estimatedTimeSavedMs: 400,
      );
      final s2 = LintCacheStats(
        entryCount: 3,
        approximateBytes: 256,
        hitCount: 4,
        missCount: 6,
        invalidationCount: 2,
        oldestEntryAt: a,
        newestEntryAt: b,
        averageRunDurationMs: 100,
        estimatedTimeSavedMs: 400,
      );
      expect(s1, equals(s2));
      expect(s1.hashCode, equals(s2.hashCode));
    });
  });
}
