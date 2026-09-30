// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/violation_trend_data_point.dart';

void main() {
  group('ViolationTrendDataPoint', () {
    test('equality is value-based', () {
      final t = DateTime.utc(2026, 5, 25, 10);
      final a = ViolationTrendDataPoint(
        runId: 'r1',
        runTimestamp: t,
        ruleId: 'verilator/UNUSEDSIGNAL',
        severity: Severity.warning,
        filePath: '/p/a.sv',
        lineNumber: 42,
        message: 'signal unused',
      );
      final b = ViolationTrendDataPoint(
        runId: 'r1',
        runTimestamp: t,
        ruleId: 'verilator/UNUSEDSIGNAL',
        severity: Severity.warning,
        filePath: '/p/a.sv',
        lineNumber: 42,
        message: 'signal unused',
      );
      final c = ViolationTrendDataPoint(
        runId: 'r2',
        runTimestamp: t,
        ruleId: 'verilator/UNUSEDSIGNAL',
        severity: Severity.warning,
        filePath: '/p/a.sv',
        lineNumber: 42,
        message: 'signal unused',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('lineNumber is optional', () {
      final p = ViolationTrendDataPoint(
        runId: 'r1',
        runTimestamp: DateTime.utc(2026, 5, 25),
        ruleId: 'verilator/X',
        severity: Severity.error,
        filePath: '/p/a.sv',
        message: 'm',
      );
      expect(p.lineNumber, isNull);
    });
  });
}
