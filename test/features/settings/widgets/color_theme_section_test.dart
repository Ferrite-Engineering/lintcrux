// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/theme/lintcrux_color_theme_bootstrap.dart';
import 'package:lintcrux/core/theme/lintcrux_theme_tokens.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/features/settings/widgets/color_theme_section.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// Pumps [ColorThemeSection] with a stubbed pack-directory resolver so
/// the widget tree never hits `path_provider`.
Future<Directory> pumpSection(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  Future<String?> Function()? pickPackDocument,
  Future<String?> Function(String document)? savePackDocument,
}) async {
  final tmp = Directory.systemTemp.createTempSync('lintcrux_theme_test_');
  addTearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [lintcruxCruxColorThemeOverride],
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
          body: SingleChildScrollView(
            child: ColorThemeSection(
              packDirectoryResolver: () async => tmp,
              pickPackDocument: pickPackDocument,
              savePackDocument: savePackDocument,
            ),
          ),
        ),
      ),
    ),
  );
  // Resolve the pack-directory FutureBuilder and the ThemePackBrowser's
  // internal pack-list FutureBuilder.
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return tmp;
}

void main() {
  setUpAll(registerLintcruxThemeTokens);

  group('ColorThemeSection composition', () {
    testWidgets(
      'renders a preset picker, token override sections, and a theme '
      'pack browser',
      (tester) async {
        await pumpSection(tester);
        expect(tester.takeException(), isNull);

        expect(find.byType(PresetPicker), findsOneWidget);
        expect(find.byType(TokenCategorySection), findsWidgets);
        expect(find.byType(ThemePackBrowser), findsOneWidget);
      },
    );

    testWidgets('renders one preset card per built-in preset', (
      tester,
    ) async {
      await pumpSection(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(PresetCard), findsNWidgets(builtinPresets().length));
    });
  });

  group('preset activation persists to AppSettings', () {
    testWidgets(
      'tapping a preset card activates cruxColorThemeProvider AND '
      'persists activeThemeName to appSettingsProvider',
      (tester) async {
        tester.view.physicalSize = const Size(1600 * 3, 1200 * 3);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await pumpSection(tester);
        expect(tester.takeException(), isNull);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(ColorThemeSection)),
        );
        // Default preset is Crux Dark — activating a different
        // built-in preset is a real state transition.
        expect(
          container.read(appSettingsProvider).core.activeThemeName,
          'crux-dark',
        );

        final lightCard = find.ancestor(
          of: find.text('Crux Light'),
          matching: find.byType(PresetCard),
        );
        expect(lightCard, findsOneWidget);
        await tester.tap(lightCard, warnIfMissed: false);
        await tester.pump();

        expect(container.read(cruxColorThemeProvider).id, 'crux-light');
        expect(
          container.read(appSettingsProvider).core.activeThemeName,
          'crux-light',
        );
      },
    );
  });

  group('file-picker callbacks', () {
    testWidgets(
      'the theme pack browser import button invokes pickPackDocument',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1600 * 3, 1200 * 3);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        var invoked = false;
        await pumpSection(
          tester,
          pickPackDocument: () async {
            invoked = true;
            return null;
          },
        );
        expect(tester.takeException(), isNull);

        final importButton = find.descendant(
          of: find.byType(ThemePackBrowser),
          matching: find.byType(FilledButton),
        );
        expect(importButton, findsOneWidget);
        await tester.tap(importButton, warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(invoked, isTrue);
      },
    );

    testWidgets(
      'the theme pack browser export button invokes savePackDocument',
      (tester) async {
        tester.view.physicalSize = const Size(1600 * 3, 1200 * 3);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        var invoked = false;
        await pumpSection(
          tester,
          savePackDocument: (document) async {
            invoked = true;
            return null;
          },
        );
        expect(tester.takeException(), isNull);

        final exportButton = find.descendant(
          of: find.byType(ThemePackBrowser),
          matching: find.byType(OutlinedButton),
        );
        expect(exportButton, findsOneWidget);
        await tester.tap(exportButton, warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(invoked, isTrue);
      },
    );
  });

  group('pack directory resolution fallback', () {
    testWidgets(
      'a failing packDirectoryResolver still renders the section, '
      'falling back to systemTemp',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [lintcruxCruxColorThemeOverride],
            child: MaterialApp(
              localizationsDelegates: const [
                L10N.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                // Scrolled like every other test in this file (and like the
                // real Settings shell, whose sections self-scroll): this
                // test is about the resolver fallback, not about fitting
                // the whole Appearance section in an 800x600 viewport.
                body: SingleChildScrollView(
                  child: ColorThemeSection(
                    packDirectoryResolver: () =>
                        throw const FileSystemException('boom'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
        expect(find.byType(ThemePackBrowser), findsOneWidget);
      },
    );
  });

  group('locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders without exception in $locale', (tester) async {
        await pumpSection(tester, locale: locale);
        expect(tester.takeException(), isNull);
        // NOTE: ColorThemeSection hardcodes `ThemeAppearanceStringsEn()`
        // instead of a localized `ThemeAppearanceStrings` adapter (see
        // WaveCrux's `WaveCruxThemeAppearanceStrings` for the reference
        // pattern), so the section headings below are English text
        // regardless of `locale`. That is a real localization gap in
        // the production widget, not a gap in this assertion — this
        // sweep still proves the widget renders cleanly under every
        // supported locale's `MaterialApp` context.
        expect(find.text('Presets'), findsOneWidget);
        expect(find.text('Color overrides'), findsOneWidget);
        expect(find.text('Theme packs'), findsOneWidget);
      });
    }
  });
}
