// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/shared/widgets/lintcrux_feature_tier_badge.dart';

Widget _harness(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('LintCruxFeatureTierBadge', () {
    testWidgets(
      'open-core tier renders nothing (zero-size SizedBox)',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            const LintCruxFeatureTierBadge(requiredTier: LicenseTier.openCore),
          ),
        );
        expect(find.text('PRO'), findsNothing);
        expect(find.text('ENT'), findsNothing);
      },
    );

    testWidgets('Pro tier renders the PRO chip', (tester) async {
      await tester.pumpWidget(
        _harness(const LintCruxFeatureTierBadge(requiredTier: LicenseTier.pro)),
      );
      expect(find.text('PRO'), findsOneWidget);
      expect(find.text('ENT'), findsNothing);
    });

    testWidgets('Enterprise tier renders the ENT chip', (tester) async {
      await tester.pumpWidget(
        _harness(
          const LintCruxFeatureTierBadge(requiredTier: LicenseTier.enterprise),
        ),
      );
      expect(find.text('ENT'), findsOneWidget);
      expect(find.text('PRO'), findsNothing);
    });

    testWidgets(
      'EDU tier renders nothing — EDU is a license edition rendered by '
      'EditionBadge, not a feature-required tier',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            const LintCruxFeatureTierBadge(requiredTier: LicenseTier.edu),
          ),
        );
        expect(find.text('EDU'), findsNothing);
        expect(find.text('PRO'), findsNothing);
        expect(find.text('ENT'), findsNothing);
      },
    );

    testWidgets(
      'locale sweep — renders without exceptions in en/zh_CN/ja/ko',
      (tester) async {
        const locales = [
          Locale('en'),
          Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
          Locale('ja'),
          Locale('ko'),
        ];
        for (final locale in locales) {
          await tester.pumpWidget(
            _harness(
              const LintCruxFeatureTierBadge(requiredTier: LicenseTier.pro),
              locale: locale,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason:
                'LintCruxFeatureTierBadge raised in locale ${locale.toLanguageTag()}',
          );
        }
      },
    );
  });
}
