// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/settings/screens/settings_screen.dart';
import 'package:lintcrux/features/settings/widgets/color_theme_section.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/plugins/settings_extra_sections_provider.dart';

Widget _wrap(
  Widget child, {
  Locale locale = const Locale('en'),
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        L10N.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10N.supportedLocales,
      home: child,
    ),
  );
}

void main() {
  group('SettingsScreen', () {
    testWidgets('shows the four section labels in the left rail', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const SettingsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('General'), findsWidgets);
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Engines'), findsOneWidget);
      expect(find.text('Editors'), findsOneWidget);
    });

    testWidgets('starts with the General section active', (tester) async {
      await tester.pumpWidget(_wrap(const SettingsScreen()));
      await tester.pumpAndSettle();
      // General has the "Auto-reload on source change" label.
      expect(find.text('Auto-reload on source change'), findsOneWidget);
    });

    testWidgets('switches to Appearance when its rail item is tapped', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const SettingsScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appearance').first);
      await tester.pumpAndSettle();
      // Appearance hosts only the suite-shared color-theme presets section.
      // There is no light/dark/system segmented button — brightness follows the
      // active color preset, so [ColorThemeSection] is the stable marker that
      // survives ARB-string churn from the embedded `ThemeAppearanceSection`.
      expect(find.byType(ColorThemeSection), findsOneWidget);
      expect(find.byType(SegmentedButton<AppThemeMode>), findsNothing);
    });

    testWidgets('switches to Editors when its rail item is tapped', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const SettingsScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editors').first);
      await tester.pumpAndSettle();
      expect(find.text('Click-to-source editor'), findsOneWidget);
      expect(find.text('Visual Studio Code'), findsOneWidget);
      expect(find.text('Sublime Text'), findsOneWidget);
      expect(find.text('Vim / Neovim'), findsOneWidget);
      expect(find.text('Emacs'), findsOneWidget);
      expect(find.text('Custom'), findsOneWidget);
      // Live preview is always rendered.
      expect(find.text('Live preview'), findsOneWidget);
    });

    testWidgets(
      'selecting the Custom radio reveals the executable and args fields',
      (tester) async {
        await tester.pumpWidget(_wrap(const SettingsScreen()));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Editors').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Custom'));
        await tester.pumpAndSettle();
        expect(find.text('Executable'), findsOneWidget);
        expect(find.text('Arguments template'), findsOneWidget);
      },
    );

    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders without exception in locale $locale', (
        tester,
      ) async {
        await tester.pumpWidget(_wrap(const SettingsScreen(), locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'appends Pro-contributed extra sections after the built-in rail items',
      (tester) async {
        final extras = <CruxSettingsExtraCategory>[
          CruxSettingsExtraCategory(
            id: 'pro.test',
            icon: Icons.rule,
            labelBuilder: (_) => 'My Pro Section',
            bodyBuilder: (_) => const Padding(
              padding: EdgeInsets.all(16),
              child: Text('PRO_SECTION_BODY'),
            ),
          ),
        ];
        await tester.pumpWidget(
          _wrap(
            const SettingsScreen(),
            overrides: [
              settingsExtraSectionsProvider.overrideWithValue(extras),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // The rail shows the extra label after the built-ins.
        expect(find.text('My Pro Section'), findsOneWidget);
        // The icon is rendered alongside the label.
        expect(find.byIcon(Icons.rule), findsOneWidget);
        // Built-in section is still the initial selection.
        expect(find.text('PRO_SECTION_BODY'), findsNothing);

        // Tapping the extra rail item activates its bodyBuilder.
        await tester.tap(find.text('My Pro Section'));
        await tester.pumpAndSettle();
        expect(find.text('PRO_SECTION_BODY'), findsOneWidget);
      },
    );

    testWidgets(
      'renders multiple extras in the order returned by the provider',
      (tester) async {
        final extras = <CruxSettingsExtraCategory>[
          CruxSettingsExtraCategory(
            id: 'pro.first',
            icon: Icons.extension_outlined,
            labelBuilder: (_) => 'PRO_FIRST',
            bodyBuilder: (_) => const Text('FIRST_BODY'),
          ),
          CruxSettingsExtraCategory(
            id: 'pro.second',
            icon: Icons.extension_outlined,
            labelBuilder: (_) => 'PRO_SECOND',
            bodyBuilder: (_) => const Text('SECOND_BODY'),
          ),
        ];
        await tester.pumpWidget(
          _wrap(
            const SettingsScreen(),
            overrides: [
              settingsExtraSectionsProvider.overrideWithValue(extras),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // Both rail items are visible.
        expect(find.text('PRO_FIRST'), findsOneWidget);
        expect(find.text('PRO_SECOND'), findsOneWidget);

        // Tapping each routes to its own body.
        await tester.tap(find.text('PRO_SECOND'));
        await tester.pumpAndSettle();
        expect(find.text('SECOND_BODY'), findsOneWidget);
        expect(find.text('FIRST_BODY'), findsNothing);
      },
    );
  });
}
