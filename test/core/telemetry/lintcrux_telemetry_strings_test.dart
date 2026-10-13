// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/telemetry/lintcrux_telemetry_strings.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

void main() {
  group('LintcruxTelemetryStrings', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      test('installation id row strings come from the ARB in $locale', () {
        final l10n = lookupL10N(locale);
        final strings = LintcruxTelemetryStrings(l10n);
        expect(
          strings.settingsInstallationIdNone,
          l10n.settingsTelemetryInstallationIdNone,
        );
        expect(strings.settingsInstallationIdNone, isNotEmpty);
        expect(
          strings.settingsInstallationIdLabel,
          l10n.settingsTelemetryInstallationIdLabel,
        );
        expect(
          strings.settingsInstallationIdCopied,
          l10n.settingsTelemetryInstallationIdCopied,
        );
      });
    }

    test('the empty-state line is localized, not the package default', () {
      final en = LintcruxTelemetryStrings(lookupL10N(const Locale('en')));
      final ja = LintcruxTelemetryStrings(lookupL10N(const Locale('ja')));
      expect(en.settingsInstallationIdNone, contains('usage statistics'));
      expect(
        ja.settingsInstallationIdNone,
        isNot(en.settingsInstallationIdNone),
      );
    });
  });
}
