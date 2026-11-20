// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/workspace/widgets/lintcrux_edu_status_chip.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

CruxLicenseStatus _status(LicenseTier tier) => CruxLicenseStatus(
  activation: CruxLicenseActivation.active,
  grant: LicenseGrant(
    issuerId: kEduLicenseIssuerId,
    tier: tier,
    products: const {CruxProduct.lintCrux},
    licenseId: 'lic-1',
    email: 'student@example.edu',
    expiry: DateTime.utc(2027, 8, 2, 12),
  ),
);

Widget _harness(CruxLicenseStatus status, {Locale? locale}) => ProviderScope(
  overrides: [licenseStatusProvider.overrideWithValue(status)],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      L10N.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: L10N.supportedLocales,
    home: const Scaffold(body: Center(child: LintcruxEduStatusChip())),
  ),
);

void main() {
  group('LintcruxEduStatusChip', () {
    testWidgets('EDU: the chip, the terms and the address in LintCrux words', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(_status(LicenseTier.edu)));
      expect(find.text('EDU'), findsOneWidget);
      expect(
        find.text('Non-commercial use · student@example.edu'),
        findsOneWidget,
      );
      expect(
        find.byTooltip(
          'Educational license for student@example.edu. For non-commercial '
          'teaching, learning and research only. Valid until 2027-08-02.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders nothing at open core', (tester) async {
      await tester.pumpWidget(_harness(CruxLicenseStatus.openCore));
      expect(find.byType(EditionBadge), findsNothing);
      expect(find.textContaining('Non-commercial'), findsNothing);
    });

    for (final tier in [LicenseTier.pro, LicenseTier.enterprise]) {
      testWidgets('renders nothing at ${tier.name}', (tester) async {
        await tester.pumpWidget(_harness(_status(tier)));
        expect(find.byType(EditionBadge), findsNothing);
        expect(find.textContaining('Non-commercial'), findsNothing);
      });
    }

    testWidgets('a click opens Settings at the License category', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness(_status(LicenseTier.edu)));

      await tester.tap(find.text('Non-commercial use · student@example.edu'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<CruxSettingsInitialCategory>(
              find.byType(CruxSettingsInitialCategory),
            )
            .id,
        kCruxLicenseCategoryId,
      );
    });

    for (final locale in L10N.supportedLocales) {
      testWidgets('renders the localized label in ${locale.toLanguageTag()}', (
        tester,
      ) async {
        await tester.pumpWidget(
          _harness(_status(LicenseTier.edu), locale: locale),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('student@example.edu'), findsOneWidget);
      });
    }
  });
}
