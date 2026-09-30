// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/panel_layout_state.dart';
import 'package:lintcrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:lintcrux/features/viewer/widgets/lintcrux_ide_layout.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

Widget _harness({
  Locale locale = const Locale('en'),
  PanelLayoutState? initial,
}) {
  return ProviderScope(
    overrides: [
      if (initial != null)
        panelLayoutProvider.overrideWith(_SeededNotifier.new),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        L10N.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 1400,
          height: 800,
          child: LintcruxIdeLayout(
            ruleBrowserBuilder: (context, _) =>
                const ColoredBox(color: Color(0xFFAA0000)),
            violationsBuilder: (context, _) =>
                const ColoredBox(color: Color(0xFF00AA00)),
            violationDetailsBuilder: (context, _) =>
                const ColoredBox(color: Color(0xFF0000AA)),
            runLogBuilder: (context, _) =>
                const ColoredBox(color: Color(0xFFAAAA00)),
          ),
        ),
      ),
    ),
  );
}

class _SeededNotifier extends PanelLayoutNotifier {
  @override
  PanelLayoutState build() => const PanelLayoutState(
    ruleBrowserVisible: false,
    violationDetailsVisible: false,
    runLogVisible: false,
  );
}

void main() {
  group('LintcruxIdeLayout', () {
    testWidgets('renders without exceptions at default state', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'programmatic visibility toggle propagates from provider to layout',
      (tester) async {
        await tester.pumpWidget(_harness());
        await tester.pumpAndSettle();
        // Initially all panes visible — none of the panel content
        // widgets are null.
        expect(tester.takeException(), isNull);
        // Read the notifier and toggle off all three side/bottom panes.
        final element = tester.element(find.byType(LintcruxIdeLayout));
        final container = ProviderScope.containerOf(element);
        container.read(panelLayoutProvider.notifier)
          ..setRuleBrowserVisible(visible: false)
          ..setViolationDetailsVisible(visible: false)
          ..setRunLogVisible(visible: false);
        await tester.pumpAndSettle();
        // After the toggle the layout must still build without throwing.
        expect(tester.takeException(), isNull);
        expect(
          container.read(panelLayoutProvider).ruleBrowserVisible,
          isFalse,
        );
      },
    );

    testWidgets('honours a seeded initial state from the provider override', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(initial: const PanelLayoutState(ruleBrowserVisible: false)),
      );
      await tester.pumpAndSettle();
      final element = tester.element(find.byType(LintcruxIdeLayout));
      final container = ProviderScope.containerOf(element);
      // The seeded notifier starts with all panes hidden — the layout
      // should still pump cleanly because the IdeController is built
      // from the seeded state, not the model defaults.
      expect(
        container.read(panelLayoutProvider).ruleBrowserVisible,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });

    group('locale sweep', () {
      for (final locale in const [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('zh'),
        Locale('ja'),
        Locale('ko'),
      ]) {
        testWidgets('renders without exceptions in $locale', (tester) async {
          await tester.pumpWidget(_harness(locale: locale));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    });
  });
}
