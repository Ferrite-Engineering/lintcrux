// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/lint_run_completion_event.dart';
import 'package:lintcrux/domain/models/violation_trend_data_point.dart';
import 'package:lintcrux/services/trends/lint_run_completion_event_bus.dart';
import 'package:lintcrux/services/trends/lint_run_completion_event_provider.dart';

LintRunCompletionEvent _event({String runId = 'r1'}) {
  final ts = DateTime.utc(2026, 7, 20);
  return LintRunCompletionEvent(
    runId: runId,
    runTimestamp: ts,
    dataPoints: <ViolationTrendDataPoint>[
      ViolationTrendDataPoint(
        runId: runId,
        runTimestamp: ts,
        ruleId: 'verilator/UNUSED',
        severity: Severity.warning,
        filePath: '/p/a.sv',
        message: 'unused',
      ),
    ],
  );
}

void main() {
  group('LintRunCompletionEventBus', () {
    test('emit reaches subscribers; emit after dispose is a no-op', () async {
      final bus = LintRunCompletionEventBus();
      final seen = <LintRunCompletionEvent>[];
      final sub = bus.events.listen(seen.add);
      addTearDown(sub.cancel);

      bus.emit(_event());
      await Future<void>.delayed(Duration.zero);
      expect(seen, hasLength(1));

      await bus.dispose();
      // No throw after dispose.
      expect(() => bus.emit(_event(runId: 'r2')), returnsNormally);
    });
  });

  group('lintRunCompletionEventProvider', () {
    test('republishes events emitted into the root bus', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final captured = <LintRunCompletionEvent>[];
      final sub = container.listen(
        lintRunCompletionEventProvider,
        (_, next) => next.whenData(captured.add),
      );
      addTearDown(sub.close);
      // Let the StreamProvider attach to the broadcast bus stream.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      container.read(lintRunCompletionEventBusProvider).emit(_event());
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (captured.isNotEmpty) break;
      }
      expect(captured, hasLength(1));
      expect(captured.single.runId, 'r1');
    });
  });
}
