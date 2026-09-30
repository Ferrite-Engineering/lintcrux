// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/help_urls.dart';
import 'package:lintcrux/features/update/lintcrux_update_config.dart';

void main() {
  group('lintcruxUpdateConfig', () {
    test('names the product and points at the LintCrux endpoints', () {
      expect(lintcruxUpdateConfig.productName, 'LintCrux');
      expect(
        lintcruxUpdateConfig.manifestUri.toString(),
        'https://updates.lintcrux.app/manifest.json',
      );
      expect(
        lintcruxUpdateConfig.downloadPageUri.toString(),
        'https://lintcrux.app/download',
      );
    });

    test('shares its download page with the beta-expiry gate', () {
      // Both surfaces send the user to the same place; a drift here would
      // strand an expired-beta user on a page with no current build.
      expect(
        lintcruxUpdateConfig.downloadPageUri.toString(),
        HelpUrls.download,
      );
    });

    test('declares no store listings — LintCrux has no mobile target', () {
      expect(lintcruxUpdateConfig.appStoreUri, isNull);
      expect(lintcruxUpdateConfig.playStoreUri, isNull);
    });

    test('does not check on mobile', () {
      // There is no iOS/Android LintCrux build; leaving this false means a
      // hypothetical mobile host makes no outbound request at all.
      expect(lintcruxUpdateConfig.checkOnMobile, isFalse);
    });

    test('every desktop platform resolves to the download page', () {
      for (final platform in <TargetPlatform>[
        TargetPlatform.macOS,
        TargetPlatform.linux,
        TargetPlatform.windows,
      ]) {
        expect(
          lintcruxUpdateConfig.updateTargetFor(platform),
          lintcruxUpdateConfig.downloadPageUri,
          reason: '$platform must resolve to the download page',
        );
      }
    });

    test('web resolves to the download page', () {
      // The banner never renders on web, but the resolution must still be
      // sane for any caller that asks.
      expect(
        lintcruxUpdateConfig.updateTargetFor(
          TargetPlatform.macOS,
          isWeb: true,
        ),
        lintcruxUpdateConfig.downloadPageUri,
      );
    });

    test('mobile falls back to the download page with no store listing', () {
      expect(
        lintcruxUpdateConfig.updateTargetFor(TargetPlatform.iOS),
        lintcruxUpdateConfig.downloadPageUri,
      );
      expect(
        lintcruxUpdateConfig.updateTargetFor(TargetPlatform.android),
        lintcruxUpdateConfig.downloadPageUri,
      );
    });
  });
}
