// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/plugins/violation_context_menu_provider.dart';

void main() {
  group('violationContextMenuEntriesProvider', () {
    test('open-core default is empty list', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final entries = container.read(violationContextMenuEntriesProvider);
      expect(entries, isEmpty);
    });

    test('Pro overlay-style override surfaces a populated list', () {
      final fakeEntry = ViolationContextMenuEntry(
        id: 'test.waive',
        labelBuilder: (_) => 'Waive…',
        requiredTier: LicenseTier.pro,
        onActivate: (_, _, _) {},
      );
      final container = ProviderContainer(
        overrides: [
          violationContextMenuEntriesProvider.overrideWithValue(
            [fakeEntry],
          ),
        ],
      );
      addTearDown(container.dispose);

      final entries = container.read(violationContextMenuEntriesProvider);
      expect(entries, hasLength(1));
      expect(entries.single.id, 'test.waive');
      // labelBuilder runs against the row widget's `BuildContext` at
      // popup-build time. Exercise it inside a pumped widget so the
      // function is callable; the Pro override resolves L10NPro at
      // that point and the fake here just returns a literal.
      expect(entries.single.requiredTier, LicenseTier.pro);
    });

    testWidgets('labelBuilder resolves against the row BuildContext', (
      tester,
    ) async {
      String? rendered;
      final entry = ViolationContextMenuEntry(
        id: 'test',
        labelBuilder: (_) => 'Waive…',
        onActivate: (_, _, _) {},
      );
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            rendered = entry.labelBuilder(context);
            return const SizedBox.shrink();
          },
        ),
      );
      expect(rendered, 'Waive…');
    });

    test('default requiredTier is openCore', () {
      final entry = ViolationContextMenuEntry(
        id: 'test',
        labelBuilder: (_) => 'Test',
        onActivate: (_, _, _) {},
      );
      expect(entry.requiredTier, LicenseTier.openCore);
    });
  });
}
