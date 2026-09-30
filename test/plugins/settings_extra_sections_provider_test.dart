// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/plugins/settings_extra_sections_provider.dart';

void main() {
  group('settingsExtraSectionsProvider', () {
    test('open-core default is an empty list', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final sections = container.read(settingsExtraSectionsProvider);
      expect(sections, isEmpty);
    });

    test(
      'Pro overlay-style override returns the supplied entries in order '
      '(suite-shared CruxSettingsExtraCategory shape)',
      () {
        final entries = <CruxSettingsExtraCategory>[
          CruxSettingsExtraCategory(
            id: 'pro.custom_rules',
            icon: Icons.rule,
            labelBuilder: (_) => 'Custom Rules',
            bodyBuilder: (_) => const SizedBox.shrink(),
          ),
          CruxSettingsExtraCategory(
            id: 'pro.trend',
            icon: Icons.show_chart,
            labelBuilder: (_) => 'Trend',
            bodyBuilder: (_) => const SizedBox.shrink(),
          ),
        ];
        final container = ProviderContainer(
          overrides: [
            settingsExtraSectionsProvider.overrideWithValue(entries),
          ],
        );
        addTearDown(container.dispose);

        final read = container.read(settingsExtraSectionsProvider);
        expect(read, hasLength(2));
        expect(read[0].id, 'pro.custom_rules');
        expect(read[0].icon, Icons.rule);
        expect(read[1].id, 'pro.trend');
        expect(read[1].icon, Icons.show_chart);
      },
    );

    testWidgets('labelBuilder resolves against the Settings BuildContext', (
      tester,
    ) async {
      String? rendered;
      final entry = CruxSettingsExtraCategory(
        id: 'pro.custom_rules',
        icon: Icons.rule,
        labelBuilder: (_) => 'Custom Rules',
        bodyBuilder: (_) => const SizedBox.shrink(),
      );
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            rendered = entry.labelBuilder(context);
            return const SizedBox.shrink();
          },
        ),
      );
      expect(rendered, 'Custom Rules');
    });

    testWidgets('bodyBuilder receives a live BuildContext (provider-aware '
        'bodies return a Consumer)', (tester) async {
      var built = false;
      final entry = CruxSettingsExtraCategory(
        id: 'pro.custom_rules',
        icon: Icons.rule,
        labelBuilder: (_) => 'Custom Rules',
        bodyBuilder: (context) {
          built = true;
          expect(context, isA<BuildContext>());
          return const SizedBox.shrink();
        },
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(builder: entry.bodyBuilder),
          ),
        ),
      );
      expect(built, isTrue);
    });

    test('entry equality is reference-based (entries are not const)', () {
      final a = CruxSettingsExtraCategory(
        id: 'pro.x',
        icon: Icons.rule,
        labelBuilder: (_) => 'X',
        bodyBuilder: (_) => const SizedBox.shrink(),
      );
      final b = CruxSettingsExtraCategory(
        id: 'pro.x',
        icon: Icons.rule,
        labelBuilder: (_) => 'X',
        bodyBuilder: (_) => const SizedBox.shrink(),
      );
      // No deep equality contract — different instances are not equal
      // even with the same id. This matches how `ViolationContextMenuEntry`
      // is used: the provider list itself is the identity carrier.
      expect(identical(a, b), isFalse);
      expect(a == b, isFalse);
    });
  });
}
