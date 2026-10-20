// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/settings/widgets/settings_remote_control_section.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/remote/cxp/lintcrux_cxp_binding.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The page under test, with the shared CXP settings bound the way
/// `bootstrap()` binds them. The transport is off, so no server binds.
Widget _wrap({
  CruxCxpSettings launch = const CruxCxpSettings(enabled: true, port: 54324),
  Locale locale = const Locale('en'),
  List<Override> extra = const [],
  void Function(ProviderContainer container)? onContainer,
}) {
  return ProviderScope(
    overrides: [
      cruxCxpProductBindingProvider.overrideWithValue(kLintcruxCxpBinding),
      cruxCxpLaunchSettingsProvider.overrideWithValue(launch),
      cruxCxpTransportAvailableProvider.overrideWithValue(false),
      ...extra,
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
      home: Consumer(
        builder: (context, ref, _) {
          onContainer?.call(ProviderScope.containerOf(context));
          return const Scaffold(body: SettingsRemoteControlSection());
        },
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('SettingsRemoteControlSection', () {
    testWidgets('renders the enabled switch and port field', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      // Three switches: the CXP-enabled toggle, the request-attention
      // toggle, and the broadcast-selection toggle.
      expect(find.byType(Switch), findsNWidgets(3));
      expect(find.byType(TextField), findsOneWidget);
      // Port defaults to 54324.
      expect(find.text('54324'), findsOneWidget);
    });

    testWidgets('toggling the switch saves the enabled setting at once', (
      tester,
    ) async {
      late ProviderContainer container;
      await tester.pumpWidget(_wrap(onContainer: (c) => container = c));
      await tester.pumpAndSettle();
      // Toggle the CXP-enabled switch (the first one) off.
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(container.read(cruxCxpSettingsProvider).enabled, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('settings.cxpServerEnabled'), isFalse);
    });

    testWidgets('toggling the attention switch saves it at once', (
      tester,
    ) async {
      late ProviderContainer container;
      await tester.pumpWidget(_wrap(onContainer: (c) => container = c));
      await tester.pumpAndSettle();
      // The request-attention switch is the second (defaults on).
      expect(container.read(cruxCxpSettingsProvider).requestAttention, isTrue);
      await tester.tap(find.byType(Switch).at(1));
      await tester.pumpAndSettle();
      expect(container.read(cruxCxpSettingsProvider).requestAttention, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('settings.requestAttentionOnCrossProbe'), isFalse);
    });

    testWidgets('toggling the broadcast-selection switch saves it at once', (
      tester,
    ) async {
      late ProviderContainer container;
      await tester.pumpWidget(_wrap(onContainer: (c) => container = c));
      await tester.pumpAndSettle();
      // The broadcast-selection switch is the third (defaults on).
      expect(
        container.read(cruxCxpSettingsProvider).broadcastSelection,
        isTrue,
      );
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();
      expect(
        container.read(cruxCxpSettingsProvider).broadcastSelection,
        isFalse,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool('settings.broadcastSelectionOnCrossProbe'),
        isFalse,
      );
    });

    testWidgets('a new port is saved under the LintCrux key', (tester) async {
      late ProviderContainer container;
      await tester.pumpWidget(_wrap(onContainer: (c) => container = c));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '60000');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(container.read(cruxCxpSettingsProvider).port, 60000);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('settings.cxpServerPort'), 60000);
    });

    testWidgets('disables the port field when the switch is off', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(launch: const CruxCxpSettings(enabled: false, port: 54324)),
      );
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse);
    });

    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(_wrap(locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'lays out Enable → Port → Request-attention → Broadcast-selection → '
      'CXP Status top-to-bottom (WaveCrux canonical order)',
      (tester) async {
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();

        final enableDy = tester.getTopLeft(find.text('Enable CXP server')).dy;
        final portDy = tester.getTopLeft(find.byType(TextField)).dy;
        final attentionDy = tester
            .getTopLeft(find.text('Request attention on cross-probe'))
            .dy;
        final broadcastDy = tester
            .getTopLeft(find.text('Broadcast selection automatically'))
            .dy;
        // The CXP Status line closes the section.
        final statusDy = tester.getTopLeft(find.text('CXP status')).dy;

        expect(enableDy, lessThan(portDy));
        expect(portDy, lessThan(attentionDy));
        expect(attentionDy, lessThan(broadcastDy));
        expect(broadcastDy, lessThan(statusDy));
      },
    );

    testWidgets('CXP Status shows "Stopped" when the server is not running', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.text('CXP status'), findsOneWidget);
      expect(find.text('Stopped'), findsOneWidget);
    });

    testWidgets('keeps the documentation link beside the section', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.byType(CruxCxpSettingsSection), findsOneWidget);
      expect(find.byTooltip('Learn more'), findsOneWidget);
    });

    testWidgets('the keyboard walk names every stop in the section', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      tester.view
        ..physicalSize = const Size(1200, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final walk = await walkFocus(tester);
      expectCleanFocusWalk(walk, context: 'Settings CXP Cross-Probe section');
      expectFocusWalkGolden(
        walk,
        'test/accessibility/goldens/settings_cxp_section.txt',
      );
      handle.dispose();
    });
  });
}
