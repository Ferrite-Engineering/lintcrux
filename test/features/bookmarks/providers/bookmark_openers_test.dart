// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/bookmarks/providers/bookmark_openers.dart';
import 'package:lintcrux/features/bookmarks/screens/bookmark_panel.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

import '../../../support/telemetry_test_store.dart';

Future<BuildContext> _pumpHost(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  late BuildContext ctx;
  await tester.pumpWidget(
    ProviderScope(
      overrides: telemetryDeclinedOverrides(),
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
            ctx = context;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return ctx;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pump();
}

void main() {
  group('bookmark openers', () {
    test('both openers are bound by default', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(bookmarkPanelOpenerProvider), isNotNull);
      expect(container.read(toggleBookmarkOpenerProvider), isNotNull);
    });

    testWidgets('the panel opener mounts the BookmarkPanel', (tester) async {
      final ctx = await _pumpHost(tester);
      expect(find.byType(BookmarkPanel), findsNothing);
      final opener = ProviderScope.containerOf(
        ctx,
      ).read(bookmarkPanelOpenerProvider);
      expect(opener, isNotNull);
      opener?.call(ctx);
      await _settle(tester);
      expect(find.byType(BookmarkPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    group('locale sweep', () {
      for (final loc in const [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('ja'),
        Locale('ko'),
      ]) {
        testWidgets(
          'the toggle opener with no selection says a violation must be '
          'selected (${loc.languageCode})',
          (tester) async {
            final ctx = await _pumpHost(tester, locale: loc);
            final opener = ProviderScope.containerOf(
              ctx,
            ).read(toggleBookmarkOpenerProvider);
            expect(opener, isNotNull);
            opener?.call(ctx);
            await _settle(tester);
            expect(
              find.text(L10N.of(ctx).bookmarkNoSelectionSnackbar),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    });
  });
}
