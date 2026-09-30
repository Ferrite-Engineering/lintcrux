// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/features/settings/widgets/settings_general_section.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

const _locales = ['en', 'zh_CN', 'zh', 'ja', 'ko'];
const _toggleKey = Key('settings.autoCheckForUpdates');
const _restoreTabsKey = Key('settings.restoreTabsOnLaunch');
const _diagnosticsKey = Key('settings.diagnosticsEnabled');

Locale _locale(String tag) {
  final parts = tag.split('_');
  return parts.length == 2 ? Locale(parts[0], parts[1]) : Locale(parts[0]);
}

Widget _harness({String locale = 'en', bool releaseBuild = false}) =>
    ProviderScope(
      overrides: [
        diagnosticsForcedByBuildModeProvider.overrideWithValue(!releaseBuild),
      ],
      child: MaterialApp(
        locale: _locale(locale),
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: const Scaffold(body: SettingsGeneralSection()),
      ),
    );

ProviderContainer _containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(SettingsGeneralSection)),
      listen: false,
    );

void main() {
  group('SettingsGeneralSection — automatic update check', () {
    testWidgets('renders the toggle, on by default', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.byKey(_toggleKey), findsOneWidget);
      final tile = tester.widget<SwitchListTile>(find.byKey(_toggleKey));
      expect(tile.value, isTrue);

      final l10n = lookupL10N(const Locale('en'));
      expect(find.text(l10n.settingsAutoCheckUpdatesLabel), findsOneWidget);
      expect(
        find.text(l10n.settingsAutoCheckUpdatesDescription),
        findsOneWidget,
      );
    });

    testWidgets('toggling off updates the settings model', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      // The shared auto-reload tile above is taller than the old inline
      // control; bring the toggle on screen before tapping.
      await tester.ensureVisible(find.byKey(_toggleKey));
      await tester.pump();
      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();

      expect(
        _containerOf(tester).read(appSettingsProvider).autoCheckForUpdates,
        isFalse,
      );
      expect(
        tester.widget<SwitchListTile>(find.byKey(_toggleKey)).value,
        isFalse,
      );
    });

    testWidgets('toggling back on restores the default', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      // The shared auto-reload tile above is taller than the old inline
      // control; bring the toggle on screen before tapping.
      await tester.ensureVisible(find.byKey(_toggleKey));
      await tester.pump();
      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();

      expect(
        _containerOf(tester).read(appSettingsProvider).autoCheckForUpdates,
        isTrue,
      );
    });

    testWidgets('the toggle row clears the 44 dp touch target', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(_toggleKey)).height,
        greaterThanOrEqualTo(44),
      );
    });

    for (final tag in _locales) {
      testWidgets('locale sweep renders without exceptions in $tag', (
        tester,
      ) async {
        await tester.pumpWidget(_harness(locale: tag));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(_toggleKey), findsOneWidget);
      });
    }
  });

  // Beta regression: `restoreTabsOnLaunch` had no UI anywhere in the suite, so
  // the only way to reach it was `defaults write` — which is exactly what the
  // reporter did, against a preference nothing read.
  group('SettingsGeneralSection — restore tabs on launch', () {
    testWidgets('renders the toggle, on by default', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.byKey(_restoreTabsKey), findsOneWidget);
      final tile = tester.widget<SwitchListTile>(find.byKey(_restoreTabsKey));
      expect(tile.value, isTrue);

      final l10n = lookupL10N(const Locale('en'));
      expect(
        find.text(l10n.settingsRestoreTabsOnLaunchLabel),
        findsOneWidget,
      );
      expect(
        find.text(l10n.settingsRestoreTabsOnLaunchDescription),
        findsOneWidget,
      );
    });

    testWidgets('toggling off updates the settings model', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_restoreTabsKey));
      await tester.pumpAndSettle();

      expect(
        _containerOf(tester).read(appSettingsProvider).restoreTabsOnLaunch,
        isFalse,
      );
      expect(
        tester.widget<SwitchListTile>(find.byKey(_restoreTabsKey)).value,
        isFalse,
      );
    });

    testWidgets('toggling back on restores the default', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_restoreTabsKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_restoreTabsKey));
      await tester.pumpAndSettle();

      expect(
        _containerOf(tester).read(appSettingsProvider).restoreTabsOnLaunch,
        isTrue,
      );
    });

    testWidgets('the toggle row clears the 44 dp touch target', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(_restoreTabsKey)).height,
        greaterThanOrEqualTo(44),
      );
    });

    for (final tag in _locales) {
      testWidgets('locale sweep renders without exceptions in $tag', (
        tester,
      ) async {
        await tester.pumpWidget(_harness(locale: tag));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(_restoreTabsKey), findsOneWidget);
      });
    }
  });

  group('SettingsGeneralSection — enable diagnostics', () {
    testWidgets(
      'is hidden in debug and profile builds, where diagnostics are always on',
      (tester) async {
        await tester.pumpWidget(_harness());
        await tester.pumpAndSettle();
        expect(find.byKey(_diagnosticsKey), findsNothing);
      },
    );

    testWidgets('in a release build it is shown, off by default', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(releaseBuild: true));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(_diagnosticsKey));
      expect(
        tester.widget<SwitchListTile>(find.byKey(_diagnosticsKey)).value,
        isFalse,
      );
      final l10n = lookupL10N(const Locale('en'));
      expect(find.text(l10n.settingsDiagnosticsEnabledLabel), findsOneWidget);
    });

    testWidgets('turning it on opens the diagnostics gate', (tester) async {
      await tester.pumpWidget(_harness(releaseBuild: true));
      await tester.pumpAndSettle();
      final container = _containerOf(tester);
      expect(container.read(diagnosticsEnabledProvider), isFalse);

      await tester.ensureVisible(find.byKey(_diagnosticsKey));
      await tester.pump();
      await tester.tap(find.byKey(_diagnosticsKey));
      await tester.pumpAndSettle();

      expect(container.read(appSettingsProvider).diagnosticsEnabled, isTrue);
      expect(container.read(diagnosticsEnabledProvider), isTrue);
    });

    for (final tag in _locales) {
      testWidgets('locale sweep renders the switch in $tag', (tester) async {
        await tester.pumpWidget(_harness(locale: tag, releaseBuild: true));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(_diagnosticsKey), findsOneWidget);
      });
    }
  });
}
