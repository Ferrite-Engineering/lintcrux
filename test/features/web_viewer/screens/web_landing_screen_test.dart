// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lintcrux/features/web_viewer/screens/web_landing_screen.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

Widget _harness({Locale locale = const Locale('en')}) {
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
