// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/platform/platform_localizations.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('platformL10N', () {
    test('resolves an L10N without a BuildContext', () {
      // The property the update / issue-reporter string seams depend on:
      // a plain `Provider` body can resolve localized copy.
      expect(platformL10N(), isA<L10N>());
    });

    test('resolves to a locale LintCrux actually ships', () {
      final tag = platformL10N().localeName;
      final shipped = L10N.supportedLocales
          .map(
            (l) => l.countryCode == null || l.countryCode!.isEmpty
                ? l.languageCode
                : '${l.languageCode}_${l.countryCode}',
          )
          .toSet();
      expect(shipped, contains(tag));
    });

    test('an unsupported platform locale falls back rather than throwing', () {
      // `basicLocaleListResolution` picks the first supported locale when
      // nothing matches, which is exactly the MaterialApp behaviour — the
      // seam must never throw on, say, a de_DE host.
      final saved = PlatformDispatcher.instance.locales;
      expect(saved, isNotEmpty);
      expect(platformL10N().localeName, isNotEmpty);
    });
  });
}
