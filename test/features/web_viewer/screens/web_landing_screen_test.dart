// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lintcrux/features/web_viewer/screens/web_landing_screen.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

Widget _harness({Locale locale = const Locale('en'), ThemeData? theme}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const WebLandingScreen(),
      ),
      GoRoute(
        path: '/web/viewer',
        builder: (context, state) =>
            const Scaffold(body: Text('viewer placeholder')),
      ),
    ],
  );
  return ProviderScope(
    child: MaterialApp.router(
      theme: theme,
      locale: locale,
      localizationsDelegates: const [
        L10N.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10N.supportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  group('WebLandingScreen', () {
    testWidgets('renders headline, body, file button, and URL field', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Read-Only SARIF Viewer'), findsOneWidget);
      expect(find.text('Open SARIF File…'), findsOneWidget);
      expect(find.text('SARIF URL'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    });

    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
    ]) {
      testWidgets(
        'the URL field keeps its label once it holds a URL in $locale',
        (tester) async {
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(
            _harness(
              locale: locale,
              theme: cruxThemeForDevice(
                colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
                highContrast: false,
                mobile: ThemeData.new,
                platform: TargetPlatform.macOS,
                isWeb: false,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final l10n = L10N.of(tester.element(find.byType(WebLandingScreen)));

          await tester.enterText(
            find.byType(TextField),
            'https://example.com/report.sarif',
          );
          await tester.pump();

          expect(find.text('https://example.com/report.sarif'), findsOneWidget);
          expect(find.text(l10n.webModeUrlFieldLabel), findsOneWidget);
          expect(
            tester
                .widget<TextField>(find.byType(TextField))
                .decoration
                ?.labelText,
            isNull,
          );
          expect(
            tester.getSemantics(find.byType(TextField)).label,
            contains(l10n.webModeUrlFieldLabel),
          );
          semantics.dispose();
        },
      );
    }

    testWidgets('reports invalid URL when the field has bad content', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'not a real url',
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a valid http or https URL.'),
        findsOneWidget,
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
        testWidgets('renders without exceptions in $locale', (tester) async {
          await tester.pumpWidget(_harness(locale: locale));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    });
  });
}
