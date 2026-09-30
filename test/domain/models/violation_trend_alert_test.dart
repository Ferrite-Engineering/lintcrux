// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/violation_trend_alert.dart';

void main() {
  group('ViolationTrendAlert', () {
    test('equality is value-based', () {
      const a = ViolationTrendAlert(
        alertKind: ViolationTrendAlertKind.suddenSpike,
        alertSeverity: ViolationTrendAlertSeverity.warning,
        ruleId: 'verilator/X',
        baselineValue: 5,
        currentValue: 25,
        deltaPercent: 400,
        detectedAtRunId: 'r9',
      );
      const b = ViolationTrendAlert(
        alertKind: ViolationTrendAlertKind.suddenSpike,
        alertSeverity: ViolationTrendAlertSeverity.warning,
        ruleId: 'verilator/X',
        baselineValue: 5,
        currentValue: 25,
        deltaPercent: 400,
        detectedAtRunId: 'r9',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('severityClassDrift uses severity, not ruleId', () {
      const a = ViolationTrendAlert(
        alertKind: ViolationTrendAlertKind.severityClassDrift,
        alertSeverity: ViolationTrendAlertSeverity.critical,
        severity: Severity.error,
        baselineValue: 2,
        currentValue: 10,
        deltaPercent: 400,
        detectedAtRunId: 'r9',
      );
      expect(a.severity, Severity.error);
      expect(a.ruleId, isNull);
    });
  });
}
