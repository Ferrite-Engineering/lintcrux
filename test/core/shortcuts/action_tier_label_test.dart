// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/shortcuts/action_tier_label.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

void main() {
  group('tierLabelSuffix', () {
    for (final localeTag in const ['en', 'zh_CN', 'zh', 'ja', 'ko']) {
      group('locale $localeTag', () {
        late L10N l10n;

        setUp(() async {
          final locale = localeTag.contains('_')
              ? Locale(localeTag.split('_')[0], localeTag.split('_')[1])
              : Locale(localeTag);
          l10n = await L10N.delegate.load(locale);
        });

        test('open-core and edu produce no suffix', () {
          expect(tierLabelSuffix(LicenseTier.openCore, l10n), isEmpty);
          expect(tierLabelSuffix(LicenseTier.edu, l10n), isEmpty);
        });

        test('pro and enterprise produce parenthetical tier suffixes', () {
          final pro = tierLabelSuffix(LicenseTier.pro, l10n);
          final ent = tierLabelSuffix(LicenseTier.enterprise, l10n);
          // Leading space so it appends cleanly to a label.
          expect(pro, startsWith(' '));
          expect(ent, startsWith(' '));
          expect(pro, contains(l10n.tierBadgePro));
          expect(ent, contains(l10n.tierBadgeEnterprise));
          expect(pro, isNot(equals(ent)));
        });
      });
    }
  });
}
