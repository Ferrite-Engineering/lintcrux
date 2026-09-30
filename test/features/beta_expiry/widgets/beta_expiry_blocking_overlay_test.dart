// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/beta_expiry/beta_expiry_metrics.dart';
import 'package:lintcrux/features/beta_expiry/widgets/beta_expiry_blocking_overlay.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

const _locales = ['en', 'zh_CN', 'zh', 'ja', 'ko'];

Locale _locale(String tag) {
  final parts = tag.split('_');
  return parts.length == 2 ? Locale(parts[0], parts[1]) : Locale(parts[0]);
}

Widget _harness({
  required VoidCallback onDownload,
  required VoidCallback onQuit,
  String locale = 'en',
}) => MaterialApp(
  locale: _locale(locale),
  localizationsDelegates: L10N.localizationsDelegates,
  supportedLocales: L10N.supportedLocales,
  home: Scaffold(
    body: BetaExpiryBlockingOverlay(
      onDownload: onDownload,
      onQuit: onQuit,
      child: const Center(child: Text('routed-content')),
    ),
  ),
);

void main() {
  group('BetaExpiryBlockingOverlay', () {
    testWidgets('renders the routed content behind a blocking barrier', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(onDownload: () {}, onQuit: () {}));
      expect(find.text('routed-content'), findsOneWidget);
      // `MaterialApp` mounts barriers of its own, so assert that at least one
      // NON-dismissible barrier is present rather than that exactly one is.
      final barriers = tester
          .widgetList<ModalBarrier>(find.byType(ModalBarrier))
          .where((b) => !b.dismissible);
      expect(barriers, isNotEmpty);
    });

    testWidgets('blocks the system back gesture', (tester) async {
      await tester.pumpWidget(_harness(onDownload: () {}, onQuit: () {}));
      // `PopScope` is generic and the overlay leaves the type argument to
      // inference, so match on the raw type rather than a spelled-out one.
      final blocking = tester
          .widgetList<Widget>(
            find.byWidgetPredicate((w) => w is PopScope<dynamic>),
          )
          .cast<PopScope<dynamic>>()
          .where((p) => !p.canPop);
      expect(blocking, isNotEmpty);
    });

    testWidgets('the download action fires onDownload', (tester) async {
      var downloads = 0;
      await tester.pumpWidget(
        _harness(onDownload: () => downloads++, onQuit: () {}),
      );
      await tester.tap(
        find.text(lookupL10N(const Locale('en')).betaExpiryExpiredAction),
      );
      await tester.pump();
      expect(downloads, 1);
    });

    testWidgets('the quit action fires onQuit', (tester) async {
      // Load-bearing on Windows and Linux, where the window close button is
      // behind the barrier: without this the modal is a dead end.
      var quits = 0;
      await tester.pumpWidget(
        _harness(onDownload: () {}, onQuit: () => quits++),
      );
      await tester.tap(
        find.text(lookupL10N(const Locale('en')).betaExpiryExpiredQuit),
      );
      await tester.pump();
      expect(quits, 1);
    });

    testWidgets('both actions meet the 44 dp touch target', (tester) async {
      await tester.pumpWidget(_harness(onDownload: () {}, onQuit: () {}));
      for (final finder in <Finder>[
        find.byType(FilledButton),
        find.byType(TextButton),
      ]) {
        expect(
          tester.getSize(finder).height,
          greaterThanOrEqualTo(BetaExpiryMetrics.touchTarget),
        );
      }
    });

    for (final tag in _locales) {
      testWidgets('locale sweep renders without exceptions in $tag', (
        tester,
      ) async {
        await tester.pumpWidget(
          _harness(onDownload: () {}, onQuit: () {}, locale: tag),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
