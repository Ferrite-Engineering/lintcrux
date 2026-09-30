// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/lint_run_completion_event.dart';
import 'package:lintcrux/domain/models/violation_trend_data_point.dart';

void main() {
  group('LintRunCompletionEvent', () {
    test('equality compares dataPoints by index', () {
      final t = DateTime.utc(2026, 5, 25);
      final p1 = ViolationTrendDataPoint(
        runId: 'r1',
        runTimestamp: t,
        ruleId: 'verilator/X',
        severity: Severity.warning,
        filePath: '/p/a.sv',
        message: 'm',
      );
      final p2 = ViolationTrendDataPoint(
        runId: 'r1',
        runTimestamp: t,
        ruleId: 'verilator/Y',
        severity: Severity.error,
        filePath: '/p/a.sv',
        message: 'm',
      );
      final a = LintRunCompletionEvent(
        runId: 'r1',
        runTimestamp: t,
        dataPoints: [p1, p2],
      );
      final b = LintRunCompletionEvent(
        runId: 'r1',
        runTimestamp: t,
        dataPoints: [p1, p2],
      );
      final c = LintRunCompletionEvent(
        runId: 'r1',
        runTimestamp: t,
        dataPoints: [p2, p1], // order swap
      );
      expect(a, b);
      expect(a, isNot(c));
    });

    test('equality includes projectPath; default is null', () {
      final t = DateTime.utc(2026, 5, 25);
      final base = LintRunCompletionEvent(
        runId: 'r1',
        runTimestamp: t,
        dataPoints: const [],
      );
      final withProject = LintRunCompletionEvent(
        runId: 'r1',
        runTimestamp: t,
        dataPoints: const [],
        projectPath: '/work/demo',
      );
      final withProjectAgain = LintRunCompletionEvent(
        runId: 'r1',
        runTimestamp: t,
        dataPoints: const [],
        projectPath: '/work/demo',
      );
      expect(base.projectPath, isNull);
      expect(withProject, withProjectAgain);
      expect(withProject.hashCode, withProjectAgain.hashCode);
      expect(base, isNot(withProject));
      expect(withProject.toString(), contains('/work/demo'));
    });
  });
}
