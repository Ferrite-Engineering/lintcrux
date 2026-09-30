// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/trend_retention_policy.dart';

void main() {
  group('TrendRetentionPolicy', () {
    test('proDefault is 90 days / 1000 runs / oldestFirst', () {
      expect(TrendRetentionPolicy.proDefault.maxAgeDays, 90);
      expect(TrendRetentionPolicy.proDefault.maxRunsRetained, 1000);
      expect(
        TrendRetentionPolicy.proDefault.pruneStrategy,
        TrendPruneStrategy.oldestFirst,
      );
    });

    test('equality is value-based', () {
      const a = TrendRetentionPolicy(maxAgeDays: 30, maxRunsRetained: 50);
      const b = TrendRetentionPolicy(maxAgeDays: 30, maxRunsRetained: 50);
      const c = TrendRetentionPolicy(maxAgeDays: 30, maxRunsRetained: 51);
      expect(a, b);
      expect(a, isNot(c));
    });

    test('null fields disable that constraint', () {
      const policy = TrendRetentionPolicy(maxAgeDays: 30);
      expect(policy.maxAgeDays, 30);
      expect(policy.maxRunsRetained, isNull);
    });
  });

  group('TrendStorageStats', () {
    test('empty is a sentinel for an empty store', () {
      expect(TrendStorageStats.empty.dataPointCount, 0);
      expect(TrendStorageStats.empty.distinctRunCount, 0);
      expect(TrendStorageStats.empty.oldestPointAt, isNull);
      expect(TrendStorageStats.empty.newestPointAt, isNull);
    });

    test('equality is value-based', () {
      final t = DateTime.utc(2026, 5, 25);
      final a = TrendStorageStats(
        dataPointCount: 10,
        distinctRunCount: 3,
        oldestPointAt: t,
        newestPointAt: t,
      );
      final b = TrendStorageStats(
        dataPointCount: 10,
        distinctRunCount: 3,
        oldestPointAt: t,
        newestPointAt: t,
      );
      expect(a, b);
    });
  });
}
