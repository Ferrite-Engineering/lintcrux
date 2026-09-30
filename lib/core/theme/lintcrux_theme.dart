// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:lintcrux/core/theme/lintcrux_colors.dart';

/// Builders for the LintCrux Material 3 themes.
///
/// Both light and dark themes are derived from a single brand seed
/// ([LintcruxColors.brandSeed], "lint blue" — matching the LintCrux
/// marketing website). Dark is the default — engineers stare at lint
/// dashboards for hours, and dark chrome is the engineering-tool
/// convention shared with WaveCrux, NetCrux, and SimCrux.
abstract final class LintcruxTheme {
  /// Light Material 3 theme.
  static ThemeData light() => _build(Brightness.light);

  /// Dark Material 3 theme — the LintCrux default.
  static ThemeData dark() => _build(Brightness.dark);

  /// High-contrast light theme, applied by [MaterialApp] when the OS
  /// "increase contrast" accessibility setting is on. Same brand seed as
  /// [light], driven to the maximum Material 3 contrast level.
  static ThemeData highContrastLight() =>
      _build(Brightness.light, highContrast: true);

  /// High-contrast dark theme, applied by [MaterialApp] when the OS
  /// "increase contrast" accessibility setting is on. Same brand seed as
  /// [dark], driven to the maximum Material 3 contrast level.
  static ThemeData highContrastDark() =>
      _build(Brightness.dark, highContrast: true);

  static ThemeData _build(Brightness brightness, {bool highContrast = false}) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: LintcruxColors.brandSeed,
      brightness: brightness,
      // Material 3 tonal-contrast dial: 0.0 is the standard palette, 1.0 is
      // the maximum-contrast palette WCAG-aligned for the OS accessibility
      // toggle. Keeps the brand hue rather than swapping to a fixed palette.
      contrastLevel: highContrast ? 1.0 : 0.0,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? LintcruxColors.darkCanvasBackground
          : LintcruxColors.lightCanvasBackground,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }
}
