// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/license/lintcrux_edu_notice_strings.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

Future<L10N> _l10nFor(WidgetTester tester, Locale locale) async {
  late L10N captured;
  await tester.pumpWidget(
    Localizations(
      locale: locale,
      delegates: const [
        ...L10N.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      child: Builder(
        builder: (context) {
          captured = L10N.of(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return captured;
}

const _locales = <Locale>[
  Locale('en'),
  Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
  Locale('zh'),
  Locale('ja'),
  Locale('ko'),
];

void main() {
  group('LintCruxEduNoticeStrings', () {
    testWidgets('en matches the crux_license English default', (tester) async {
      final l10n = await _l10nFor(tester, const Locale('en'));
      final strings = LintCruxEduNoticeStrings(l10n);
      const en = CruxEduNoticeStringsEn();

      expect(strings.statusLabel, en.statusLabel);
      for (final email in <String?>[null, 'student@example.edu']) {
        for (final until in <String?>[null, '2027-08-02']) {
          expect(
            strings.statusTooltip(email: email, validUntil: until),
            en.statusTooltip(email: email, validUntil: until),
            reason: 'email: $email, validUntil: $until',
          );
        }
      }
      expect(strings.exportMark('LintCrux'), en.exportMark('LintCrux'));
    });

    testWidgets('every locale fills in the email and the date', (
      tester,
    ) async {
      for (final locale in _locales) {
        final l10n = await _l10nFor(tester, locale);
        final strings = LintCruxEduNoticeStrings(l10n);
        final tag = locale.toLanguageTag();

        expect(strings.statusLabel, l10n.eduStatusLabel, reason: tag);
        expect(
          strings.statusTooltip(),
          l10n.eduStatusTooltip,
          reason: tag,
        );
        final both = strings.statusTooltip(
          email: 'student@example.edu',
          validUntil: '2027-08-02',
        );
        expect(both, contains('student@example.edu'), reason: tag);
        expect(both, contains('2027-08-02'), reason: tag);
        expect(
          strings.statusTooltip(email: 'student@example.edu'),
          allOf(contains('student@example.edu'), isNot(contains('2027'))),
          reason: tag,
        );
        expect(
          strings.statusTooltip(validUntil: '2027-08-02'),
          allOf(contains('2027-08-02'), isNot(contains('@'))),
          reason: tag,
        );
      }
    });

    // The HTML report is English throughout, and the command line writes the
    // same line, so the mark does not follow the display language.
    testWidgets('the export mark is English in every locale', (tester) async {
      for (final locale in _locales) {
        final l10n = await _l10nFor(tester, locale);
        expect(
          LintCruxEduNoticeStrings(l10n).exportMark('LintCrux'),
          'Made with LintCrux Educational · Non-commercial use only',
          reason: locale.toLanguageTag(),
        );
      }
    });
  });
}
