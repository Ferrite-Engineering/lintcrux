// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/theme/lintcrux_color_theme_bootstrap.dart';
import 'package:lintcrux/core/theme/theme_brightness_toggle.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';

void main() {
  ProviderContainer container() {
    final c = ProviderContainer(overrides: [lintcruxCruxColorThemeOverride]);
    addTearDown(c.dispose);
    return c;
  }

  void toggle(ProviderContainer c) => toggleThemeBrightness(
    c.read(cruxColorThemeProvider.notifier),
    c.read(cruxColorThemeProvider),
  );

  test('from the default dark preset it switches to Crux Light', () {
    final c = container();
    expect(c.read(cruxColorThemeProvider).brightness, Brightness.dark);
    toggle(c);
    expect(c.read(cruxColorThemeProvider).id, cruxLightPresetId);
    expect(c.read(cruxColorThemeProvider).brightness, Brightness.light);
    expect(
      c.read(appSettingsProvider).core.activeThemeName,
      cruxLightPresetId,
      reason: 'the choice is recorded where the preset picker reads it',
    );
  });

  test('pressing it again returns to Crux Dark', () {
    final c = container();
    toggle(c);
    toggle(c);
    expect(c.read(cruxColorThemeProvider).id, cruxDarkPresetId);
  });

  test('from another dark preset it lands on Crux Light', () {
    final c = container();
    final other = builtinPresets().values.firstWhere(
      (t) => t.brightness == Brightness.dark && t.id != cruxDarkPresetId,
    );
    c.read(cruxColorThemeProvider.notifier).activate(other);
    toggle(c);
    expect(c.read(cruxColorThemeProvider).id, cruxLightPresetId);
  });
}
