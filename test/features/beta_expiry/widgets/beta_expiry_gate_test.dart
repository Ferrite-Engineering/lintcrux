// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/help_urls.dart';
import 'package:lintcrux/features/beta_expiry/widgets/beta_expiry_blocking_overlay.dart';
import 'package:lintcrux/features/beta_expiry/widgets/beta_expiry_gate.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

Widget _harness({
  required BetaExpiryStatus status,
  int? daysRemaining,
  String locale = 'en',
}) => ProviderScope(
  overrides: [
    betaExpiryStatusProvider.overrideWithValue(status),
    betaExpiryDaysRemainingProvider.overrideWithValue(daysRemaining),
  ],
  child: MaterialApp(
    locale: Locale(locale),
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: const Scaffold(
      body: BetaExpiryGate(child: Center(child: Text('routed-content'))),
    ),
  ),
);

void main() {
  late List<Uri> launched;
  late int quits;
  late Future<bool> Function(Uri) savedLauncher;
  late void Function() savedExit;

  setUp(() {
    launched = <Uri>[];
    quits = 0;
    savedLauncher = betaExpiryLaunchUrl;
    savedExit = betaExpiryExitApp;
    betaExpiryLaunchUrl = (uri) async {
      launched.add(uri);
      return true;
    };
    // The real seam calls `exit(0)`, which would take the test runner with it.
    betaExpiryExitApp = () => quits++;
  });

  tearDown(() {
    betaExpiryLaunchUrl = savedLauncher;
    betaExpiryExitApp = savedExit;
  });

  group('BetaExpiryGate', () {
    testWidgets('notApplicable renders the child untouched', (tester) async {
      // The common case: every developer build and every post-beta build,
      // where `kBetaExpiry` is null.
      await tester.pumpWidget(
        _harness(status: BetaExpiryStatus.notApplicable),
      );
      expect(find.text('routed-content'), findsOneWidget);
      expect(find.byType(CruxBetaExpiryBanner), findsNothing);
      expect(find.byType(BetaExpiryBlockingOverlay), findsNothing);
    });

    testWidgets('active renders the child untouched', (tester) async {
      await tester.pumpWidget(_harness(status: BetaExpiryStatus.active));
      expect(find.text('routed-content'), findsOneWidget);
      expect(find.byType(CruxBetaExpiryBanner), findsNothing);
      expect(find.byType(BetaExpiryBlockingOverlay), findsNothing);
    });

    testWidgets('expiringSoon renders the banner above the child', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(status: BetaExpiryStatus.expiringSoon, daysRemaining: 4),
      );
      expect(find.byType(CruxBetaExpiryBanner), findsOneWidget);
      expect(find.text('routed-content'), findsOneWidget);
      expect(
        find.text(lookupL10N(const Locale('en')).betaExpiryBannerMessage(4)),
        findsOneWidget,
      );
    });

    testWidgets('dismissing the banner hides it for the session', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(status: BetaExpiryStatus.expiringSoon, daysRemaining: 4),
      );
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(find.byType(CruxBetaExpiryBanner), findsNothing);
      expect(find.text('routed-content'), findsOneWidget);
    });

    testWidgets('the banner download action opens the download page', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(status: BetaExpiryStatus.expiringSoon, daysRemaining: 2),
      );
      await tester.tap(
        find.text(lookupL10N(const Locale('en')).betaExpiryBannerAction),
      );
      await tester.pump();
      expect(launched, [Uri.parse(HelpUrls.download)]);
    });

    testWidgets('expired renders the blocking overlay', (tester) async {
      await tester.pumpWidget(_harness(status: BetaExpiryStatus.expired));
      expect(find.byType(BetaExpiryBlockingOverlay), findsOneWidget);
      expect(find.byType(CruxBetaExpiryBanner), findsNothing);
      expect(
        find.text(lookupL10N(const Locale('en')).betaExpiryExpiredTitle),
        findsOneWidget,
      );
    });

    testWidgets('the expired overlay download action opens the page', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(status: BetaExpiryStatus.expired));
      await tester.tap(
        find.text(lookupL10N(const Locale('en')).betaExpiryExpiredAction),
      );
      await tester.pump();
      expect(launched, [Uri.parse(HelpUrls.download)]);
    });

    testWidgets('the expired overlay quit action exits the app', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(status: BetaExpiryStatus.expired));
      await tester.tap(
        find.text(lookupL10N(const Locale('en')).betaExpiryExpiredQuit),
      );
      await tester.pump();
      expect(quits, 1);
    });

    for (final tag in ['en', 'zh_CN', 'zh', 'ja', 'ko']) {
      testWidgets('locale sweep — expiringSoon renders cleanly in $tag', (
        tester,
      ) async {
        await tester.pumpWidget(
          _harness(
            status: BetaExpiryStatus.expiringSoon,
            daysRemaining: 1,
            locale: tag,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });

      testWidgets('locale sweep — expired renders cleanly in $tag', (
        tester,
      ) async {
        await tester.pumpWidget(
          _harness(status: BetaExpiryStatus.expired, locale: tag),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('BetaExpiryGate — tier independence', () {
    // The gate is a build-shelf-life mechanism, not a license gate: an
    // expired beta build blocks a Pro or Enterprise licensee exactly as it
    // blocks an open-core user. Nothing in the gate reads
    // `licenseTierProvider`, and these assertions lock that in.
    for (final tier in LicenseTier.values) {
      testWidgets('$tier is still blocked by an expired build', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              licenseTierProvider.overrideWith((_) => tier),
              betaExpiryStatusProvider.overrideWithValue(
                BetaExpiryStatus.expired,
              ),
            ],
            child: const MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: BetaExpiryGate(child: Text('routed-content')),
              ),
            ),
          ),
        );
        expect(find.byType(BetaExpiryBlockingOverlay), findsOneWidget);
      });
    }
  });
}
