// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/violation_trend_aggregate.dart';

void main() {
  group('ViolationTrendAggregate', () {
    test('equality compares severityBreakdown by key/value', () {
      final start = DateTime.utc(2026, 5, 25);
      final end = start.add(const Duration(days: 1));
      final a = ViolationTrendAggregate(
        keyKind: ViolationTrendAggregateKey.perSeverity,
        keyId: Severity.warning.name,
        windowStart: start,
        windowEnd: end,
        totalRuns: 3,
        totalViolations: 12,
        distinctViolationCount: 9,
        severityBreakdown: const {Severity.warning: 12},
      );
      final b = ViolationTrendAggregate(
        keyKind: ViolationTrendAggregateKey.perSeverity,
        keyId: Severity.warning.name,
        windowStart: start,
        windowEnd: end,
        totalRuns: 3,
        totalViolations: 12,
        distinctViolationCount: 9,
        severityBreakdown: const {Severity.warning: 12},
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('global aggregate carries a null keyId', () {
      final a = ViolationTrendAggregate(
        keyKind: ViolationTrendAggregateKey.global,
        keyId: null,
        windowStart: DateTime.utc(2026),
        windowEnd: DateTime.utc(2026, 1, 2),
        totalRuns: 1,
        totalViolations: 5,
        distinctViolationCount: 5,
        severityBreakdown: const {},
      );
      expect(a.keyId, isNull);
    });
  });
}
