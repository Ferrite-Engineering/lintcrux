// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart' show Brightness;

/// Flips the active color-theme preset between Crux Light and Crux Dark.
/// Wired to `LintcruxAction.toggleTheme` (Cmd/Ctrl+Shift+K).
///
/// Brightness is driven entirely by the active color-theme preset:
/// `MaterialApp.themeMode` in `app.dart` is derived from the preset's
/// brightness via `themeModeFromBrightness`. The stored `AppThemeMode`
/// (light / dark / system) is not consulted for theming, so the toggle
/// activates the built-in preset of the opposite brightness rather than
/// writing that flag. From a non-default preset (e.g. Solarized Dark) it
/// lands on the built-in preset of the opposite brightness (Crux Light).
/// Activation goes through the LintCrux color-theme notifier, which records
/// the choice in `AppSettings.activeThemeName`.
///
/// Same behaviour as WaveCrux's toggle.
void toggleThemeBrightness(
  CruxColorThemeNotifier notifier,
  CruxColorTheme current,
) {
  final target = current.brightness == Brightness.dark
      ? cruxLightPresetId
      : cruxDarkPresetId;
  final next = builtinPresets()[target];
  if (next == null) return;
  notifier.activate(next);
}
