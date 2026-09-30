// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/update/lintcrux_update_strings.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

const _locales = ['en', 'zh_CN', 'zh', 'ja', 'ko'];

L10N _l10n(String tag) {
  final parts = tag.split('_');
  return lookupL10N(
    parts.length == 2 ? Locale(parts[0], parts[1]) : Locale(parts[0]),
  );
}

void main() {
  group('LintcruxUpdateStrings', () {
    test('every getter resolves in every shipped locale', () {
      for (final tag in _locales) {
        final strings = LintcruxUpdateStrings(_l10n(tag));
        for (final value in <String>[
          strings.bannerMessage('1.2.3'),
          strings.viewChangesAction,
          strings.updateNowAction,
          strings.dismissLabel,
          strings.checkInProgress,
          strings.checkUpToDate('1.2.3'),
          strings.checkFailed,
        ]) {
          expect(value, isNotEmpty, reason: 'empty update string in $tag');
        }
      }
    });

    test('the version is interpolated in every locale', () {
      for (final tag in _locales) {
        final strings = LintcruxUpdateStrings(_l10n(tag));
        expect(
          strings.bannerMessage('9.9.9'),
          contains('9.9.9'),
          reason: 'bannerMessage dropped the version in $tag',
        );
        expect(
          strings.checkUpToDate('9.9.9'),
          contains('9.9.9'),
          reason: 'checkUpToDate dropped the version in $tag',
        );
      }
    });

    test('the banner names the product, in every locale', () {
      // The package interpolates only the version — the product name has to
      // come from the product's own ARB entry, or the banner reads as
      // "1.2.3 is available".
      for (final tag in _locales) {
        expect(
          LintcruxUpdateStrings(_l10n(tag)).bannerMessage('1.2.3'),
          contains('LintCrux'),
          reason: 'bannerMessage omits the product name in $tag',
        );
      }
    });

    test('zh and zh_CN resolve to the same copy', () {
      final zh = LintcruxUpdateStrings(_l10n('zh'));
      final zhCn = LintcruxUpdateStrings(_l10n('zh_CN'));
      expect(zh.updateNowAction, zhCn.updateNowAction);
      expect(zh.bannerMessage('1.0.0'), zhCn.bannerMessage('1.0.0'));
    });
  });
}
