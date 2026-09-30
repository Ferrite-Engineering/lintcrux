// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/web_viewer/screens/web_viewer_screen.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/rules/rule_database_provider.dart';

/// The read-only web viewer from the keyboard: a region scope like the
/// desktop screens, so F6 moves between the app bar and the four panes.
Future<void> _pump(WidgetTester tester, {Locale? locale}) async {
  tester.view
    ..physicalSize = const Size(1600, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  // The rule browser shows a progress indicator until its database loads,
  // and that load is real async.
  await tester.runAsync(() => container.read(ruleDatabaseProvider.future));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          L10N.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10N.supportedLocales,
        home: const WebViewerScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the screen is a keyboard region scope with a named app bar', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    expect(find.byType(CruxFocusRegionScope), findsOneWidget);
    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk, context: 'web viewer');
    expect(walk.stops.first.line, startsWith('[Toolbar grouping] '));
    handle.dispose();
  });

  testWidgets('F6 moves from the app bar into the panes and back', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    final appBarAction = find.byType(TextButton);
    bool inAppBar() {
      final focus = FocusManager.instance.primaryFocus?.context;
      return focus != null &&
          find
              .descendant(of: appBarAction, matching: find.byType(Focus))
              .evaluate()
              .any((e) => e == focus || e.widget == focus.widget);
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await tester.pump();
    expect(inAppBar(), isTrue, reason: 'the first region is the app bar');

    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await tester.pump();
    expect(inAppBar(), isFalse, reason: 'F6 leaves the app bar for a pane');
    expectFocusAnnounced(tester, context: 'after F6');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(inAppBar(), isTrue, reason: 'Shift+F6 returns to the app bar');
    handle.dispose();
  });

  for (final locale in L10N.supportedLocales) {
    testWidgets('renders without exceptions in ${locale.toLanguageTag()}', (
      tester,
    ) async {
      await _pump(tester, locale: locale);
      expect(tester.takeException(), isNull);
    });
  }
}
