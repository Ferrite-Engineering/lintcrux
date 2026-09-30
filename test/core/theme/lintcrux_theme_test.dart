// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/theme/lintcrux_colors.dart';
import 'package:lintcrux/core/theme/lintcrux_theme.dart';

void main() {
  group('LintcruxTheme', () {
    test('dark() uses Material 3 with dark brightness and dark canvas', () {
      final theme = LintcruxTheme.dark();
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.dark);
      expect(
        theme.scaffoldBackgroundColor,
        LintcruxColors.darkCanvasBackground,
      );
    });

    test('light() uses Material 3 with light brightness and light canvas', () {
      final theme = LintcruxTheme.light();
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.light);
      expect(
        theme.scaffoldBackgroundColor,
        LintcruxColors.lightCanvasBackground,
      );
    });

    test('both themes derive ColorScheme from the LintCrux brand seed', () {
      // The Material 3 ColorScheme.fromSeed algorithm is deterministic, so
      // both light and dark themes should land in the same hue family
      // (lint blue) — not exactly equal (different lightness), but close.
      final dark = LintcruxTheme.dark().colorScheme;
      final light = LintcruxTheme.light().colorScheme;
      // Sanity: brightness differs but seed-derived hue family is shared.
      expect(dark.brightness, Brightness.dark);
      expect(light.brightness, Brightness.light);
      // The primary color should be derived from the brand seed; the
      // exact value depends on Material 3 internals, but the hue should
      // be in the blue range (matching the LintCrux marketing website's
      // #4DA3FF — not green, not amber, not indigo/violet). Hue in HSV is
      // the most stable property to assert.
      final darkHue = HSVColor.fromColor(dark.primary).hue;
      final lightHue = HSVColor.fromColor(light.primary).hue;
      // Blue hues fall roughly in [180, 260] degrees.
      expect(darkHue, inInclusiveRange(180, 260));
      expect(lightHue, inInclusiveRange(180, 260));
    });

    test('highContrastDark() is dark, Material 3, and dark canvas', () {
      final theme = LintcruxTheme.highContrastDark();
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.dark);
      expect(
        theme.scaffoldBackgroundColor,
        LintcruxColors.darkCanvasBackground,
      );
    });

    test('highContrastLight() is light, Material 3, and light canvas', () {
      final theme = LintcruxTheme.highContrastLight();
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.light);
      expect(
        theme.scaffoldBackgroundColor,
        LintcruxColors.lightCanvasBackground,
      );
    });

    test('high-contrast schemes differ from the standard schemes', () {
      // contrastLevel: 1.0 must actually shift the palette — otherwise the
      // OS "increase contrast" toggle would be a no-op.
      expect(
        LintcruxTheme.highContrastDark().colorScheme,
        isNot(LintcruxTheme.dark().colorScheme),
      );
      expect(
        LintcruxTheme.highContrastLight().colorScheme,
        isNot(LintcruxTheme.light().colorScheme),
      );
    });
  });
}
