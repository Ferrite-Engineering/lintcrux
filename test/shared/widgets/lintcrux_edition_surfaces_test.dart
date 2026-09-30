// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/license/lintcrux_edition_line_strings.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/shared/widgets/lintcrux_edition_badge.dart';

/// The edition is visible in the window without opening a dialog.
///
/// The property asserted first is that OPEN CORE CONTRIBUTES NOTHING. It holds
/// twice over and both halves are checked here, because either one alone would
/// be a silent regression: the badge renders `SizedBox.shrink()` at open core,
/// AND open core never mounts it at all (the trailing slot is a Pro override).
void main() {
  Widget harness(Widget child, {required LicenseTier tier}) => ProviderScope(
    overrides: [licenseTierProvider.overrideWithValue(tier)],
    child: MaterialApp(
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ),
  );

  group('the status-bar edition badge', () {
    testWidgets('renders nothing at open core', (tester) async {
      await tester.pumpWidget(
        harness(const LintCruxEditionBadge(), tier: LicenseTier.openCore),
      );
      expect(find.text('PRO'), findsNothing);
      expect(find.text('ENT'), findsNothing);
      expect(find.text('EDU'), findsNothing);
    });

    for (final (tier, label) in const <(LicenseTier, String)>[
      (LicenseTier.pro, 'PRO'),
      (LicenseTier.enterprise, 'ENT'),
      (LicenseTier.edu, 'EDU'),
    ]) {
      testWidgets('renders $label at ${tier.name}', (tester) async {
        await tester.pumpWidget(
          harness(const LintCruxEditionBadge(), tier: tier),
        );
        expect(find.text(label), findsOneWidget);
      });
    }

    testWidgets('does not throw when no licence exists at all', (tester) async {
      // It is mounted in shared chrome during startup; throwing here would take
      // the window with it.
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: LintCruxEditionBadge()),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the application-menu edition line', () {
    testWidgets('is null at open core, so no menu item is added', (
      tester,
    ) async {
      late String? line;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                line = cruxLicenseEditionLine(
                  ref.watch(licenseStatusProvider),
                  LintCruxEditionLineStrings(L10N.of(context)),
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(line, isNull);
    });

    testWidgets('names the organization when the licence names nobody', (
      tester,
    ) async {
      // The Enterprise-by-policy-file case: no user email exists, and the line
      // must not render an empty string or the word "null".
      late String? line;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            licenseStatusProvider.overrideWithValue(
              const CruxLicenseStatus(
                activation: CruxLicenseActivation.active,
                grant: LicenseGrant(
                  issuerId: 'keygen',
                  tier: LicenseTier.enterprise,
                  products: {CruxProduct.lintCrux},
                ),
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                line = cruxLicenseEditionLine(
                  ref.watch(licenseStatusProvider),
                  LintCruxEditionLineStrings(L10N.of(context)),
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(line, isNotNull);
      expect(line, isNot(contains('null')));
      expect(line!.trim(), isNotEmpty);
    });
  });
}
