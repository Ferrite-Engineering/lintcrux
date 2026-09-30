// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/baseline_violation.dart';
import 'package:lintcrux/domain/models/lint_baseline.dart';
import 'package:lintcrux/services/baseline/current_baseline_snapshot_provider.dart';

void main() {
  group('currentBaselineSnapshotProvider', () {
    test('open-core default is null (no Pro baseline set)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final snapshot = container.read(currentBaselineSnapshotProvider);
      expect(snapshot, isNull);
    });

    test(
      'Pro overlay-style override surfaces the supplied baseline synchronously',
      () {
        final baseline = LintBaseline(
          baselineId: 'b1',
          createdAt: DateTime.utc(2026, 5, 25, 10),
          projectPath: '/tmp/project',
          frozenViolations: <BaselineViolation>[
            BaselineViolation(
              ruleId: 'rule.x',
              filePath: '/tmp/project/a.sv',
              line: 42,
              message: 'msg',
              fingerprint: BaselineFingerprint.compute(
                ruleId: 'rule.x',
                filePath: '/tmp/project/a.sv',
                message: 'msg',
              ),
            ),
          ],
        );
        final container = ProviderContainer(
          overrides: [
            currentBaselineSnapshotProvider.overrideWithValue(baseline),
          ],
        );
        addTearDown(container.dispose);

        final snapshot = container.read(currentBaselineSnapshotProvider);
        expect(snapshot, same(baseline));
      },
    );
  });
}
