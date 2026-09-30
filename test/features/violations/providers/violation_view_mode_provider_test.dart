// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/violation_view_mode.dart';
import 'package:lintcrux/features/violations/providers/violation_view_mode_provider.dart';
import '../../../support/telemetry_test_store.dart';

void main() {
  group('violationViewModeProvider', () {
    test('defaults to allViolations', () {
      final container = ProviderContainer(
        overrides: telemetryDeclinedOverrides(),
      );
      addTearDown(container.dispose);

      expect(
        container.read(violationViewModeProvider),
        ViolationViewMode.allViolations,
      );
    });

    test('setMode replaces the active mode', () {
      final container = ProviderContainer(
        overrides: telemetryDeclinedOverrides(),
      );
      addTearDown(container.dispose);

      container
          .read(violationViewModeProvider.notifier)
          .setMode(ViolationViewMode.onlyNew);
      expect(
        container.read(violationViewModeProvider),
        ViolationViewMode.onlyNew,
      );

      container
          .read(violationViewModeProvider.notifier)
          .setMode(ViolationViewMode.onlyResolved);
      expect(
        container.read(violationViewModeProvider),
        ViolationViewMode.onlyResolved,
      );

      container
          .read(violationViewModeProvider.notifier)
          .setMode(ViolationViewMode.allViolations);
      expect(
        container.read(violationViewModeProvider),
        ViolationViewMode.allViolations,
      );
    });
  });
}
