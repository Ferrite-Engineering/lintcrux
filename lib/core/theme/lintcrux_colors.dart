// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// LintCrux brand color tokens.
///
/// The accent color is "lint blue" — matching the LintCrux marketing
/// website's `--color-accent` (`#4DA3FF`). Each Crux app's brand color
/// matches its website: WaveCrux teal/cyan, NetCrux amber/gold,
/// SimCrux indigo/violet, LintCrux blue. Blue reads as "calm,
/// methodical, quality signal" — appropriate for a lint dashboard,
/// without colliding with the green that engineers reflexively read as
/// "passing" in the per-violation severity column.
abstract final class LintcruxColors {
  /// Brand seed color used to derive the Material 3 [ColorScheme].
  /// "Lint blue" — matches the LintCrux website's `--color-accent`.
  static const Color brandSeed = Color(0xFF4DA3FF);

  /// Pure-black canvas background used by the violation-table surface in
  /// dark mode. Matches the WaveCrux/NetCrux convention of near-black
  /// engineering-tool backgrounds.
  static const Color darkCanvasBackground = Color(0xFF0F0F10);

  /// Light-mode canvas background.
  static const Color lightCanvasBackground = Color(0xFFFAFAFA);

  /// Severity-icon color for [Severity.fatal] — dark red, distinct from
  /// [severityError] so a fatal stands out even amid many errors.
  static const Color severityFatal = Color(0xFFB71C1C);

  /// Severity-icon color for [Severity.error] — Material red 700.
  static const Color severityError = Color(0xFFD32F2F);

  /// Severity-icon color for [Severity.warning] — amber.
  static const Color severityWarning = Color(0xFFF9A825);

  /// Severity-icon color for [Severity.note] — informational blue.
  static const Color severityNote = Color(0xFF1976D2);

  /// Severity-icon color for [Severity.none] — neutral grey.
  static const Color severityNone = Color(0xFF757575);
}
