// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/lintcrux_url_launcher.dart';
import 'package:lintcrux/features/workspace/providers/recent_projects_provider.dart';
import 'package:lintcrux/features/workspace/widgets/empty_canvas_content.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [recentProjectsProvider.overrideWithValue(const <String>[])],
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
          body: EmptyCanvasContent(
            onOpenProject: () {},
            onOpenSession: () {},
            onOpenWorkspace: () {},
            onNewProject: () {},
            onOpenRecentProject: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final opened = <Uri>[];
  setUp(() {
    opened.clear();
    lintcruxLaunchUrl = (uri) async {
      opened.add(uri);
      return true;
    };
  });

  testWidgets('the start screen carries the suite-membership line', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byKey(crux.CruxSuiteFooter.rowKey), findsOneWidget);
  });

  testWidgets('following the line opens this product’s landing path', (
    tester,
  ) async {
    await _pump(tester);
    // The peers block above it pushes the line below the fold on this
    // surface, and a tap outside the viewport silently does nothing.
    await tester.ensureVisible(find.byKey(crux.CruxSuiteFooter.rowKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(crux.CruxSuiteFooter.rowKey));
    await tester.pumpAndSettle();

    // Per-product path, not the shared `/products` page: the site's page-view
    // beacon records the path and drops the query string, so this segment is
    // the only thing that attributes the visit to LintCrux.
    expect(opened, [Uri.parse('https://edacrux.app/from/lintcrux')]);
  });

  group('More from EDACrux', () {
    testWidgets('offers the other three, and never LintCrux itself', (
      tester,
    ) async {
      await _pump(tester);
      for (final peer in crux.CruxSuiteProduct.lintCrux.peers) {
        expect(
          find.byKey(crux.CruxSuitePeers.rowKeyFor(peer)),
          findsOneWidget,
          reason: '${peer.displayName} row missing',
        );
      }
      expect(
        find.byKey(
          crux.CruxSuitePeers.rowKeyFor(crux.CruxSuiteProduct.lintCrux),
        ),
        findsNothing,
      );
    });

    testWidgets('a row lands on that product\u2019s card', (tester) async {
      await _pump(tester);
      await tester.ensureVisible(
        find.byKey(
          crux.CruxSuitePeers.rowKeyFor(crux.CruxSuiteProduct.waveCrux),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          crux.CruxSuitePeers.rowKeyFor(crux.CruxSuiteProduct.waveCrux),
        ),
      );
      await tester.pumpAndSettle();

      // Same attributable path as the footer, plus a fragment the site's
      // beacon drops before sending — so the reader lands on WaveCrux's card
      // and the visit is still recorded against LintCrux.
      expect(opened, [Uri.parse('https://edacrux.app/from/lintcrux#wavecrux')]);
    });

    testWidgets('every locale names all three products', (tester) async {
      for (final locale in const [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('zh'),
        Locale('ja'),
        Locale('ko'),
      ]) {
        await _pump(tester, locale: locale);
        expect(tester.takeException(), isNull, reason: 'locale $locale');
        for (final peer in crux.CruxSuiteProduct.lintCrux.peers) {
          // Product names are never translated.
          expect(
            find.text(peer.displayName),
            findsOneWidget,
            reason: '$locale dropped ${peer.displayName}',
          );
        }
      }
    });
  });

  testWidgets('every locale keeps the linked domain verbatim', (tester) async {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      await _pump(tester, locale: locale);
      expect(tester.takeException(), isNull, reason: 'locale $locale');

      await tester.ensureVisible(find.byKey(crux.CruxSuiteFooter.rowKey));
      await tester.pumpAndSettle();
      final rendered = tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(crux.CruxSuiteFooter.rowKey),
              matching: find.byType(Text),
            ),
          )
          .textSpan!
          .toPlainText();
      // The widget splits the sentence around this literal to underline it. A
      // translation that paraphrased the domain would render a line with
      // nothing to click, which is not a visible failure.
      expect(
        rendered,
        contains(crux.CruxSuiteFooter.defaultLinkText),
        reason: 'locale $locale dropped the linked domain',
      );
      expect(rendered, contains('EDACrux'), reason: 'locale $locale');
    }
  });
}
