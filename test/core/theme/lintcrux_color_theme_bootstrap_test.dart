// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/theme/lintcrux_color_theme_bootstrap.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(overrides: [lintcruxCruxColorThemeOverride]);
    addTearDown(container.dispose);
  });

  group('LintcruxCruxColorThemeNotifier.build', () {
    test(
      'defaults to the Crux Dark builtin preset when settings are '
      'unpersisted',
      () {
        final theme = container.read(cruxColorThemeProvider);
        expect(theme.id, 'crux-dark');
      },
    );

    test(
      'rebuilds from AppSettings.core.activeThemeName when it names a '
      'different builtin preset',
      () {
        container
            .read(appSettingsProvider.notifier)
            .setActiveThemeName('crux-light');
        final theme = container.read(cruxColorThemeProvider);
        expect(theme.id, 'crux-light');
      },
    );

    test(
      'a beta user who saved the retired wavecrux-light id still gets '
      'Light, not a silent reset to the dark default',
      () {
        // The `wavecrux-*` preset ids shipped through the public beta as
        // the shared suite default, so they are sitting in real users'
        // persisted settings. They are permanently accepted on the read
        // path via the legacy alias map; a raw `presets[name]` lookup
        // would miss and reset every Light user to Dark on upgrade.
        container
            .read(appSettingsProvider.notifier)
            .setActiveThemeName('wavecrux-light');
        expect(container.read(cruxColorThemeProvider).id, 'crux-light');
      },
    );

    test(
      'the retired wavecrux-dark id resolves to the current dark preset',
      () {
        container
            .read(appSettingsProvider.notifier)
            .setActiveThemeName('wavecrux-dark');
        expect(container.read(cruxColorThemeProvider).id, 'crux-dark');
      },
    );

    test(
      'falls back to the initial (Crux Dark) preset when the '
      'persisted theme name is unknown',
      () {
        container
            .read(appSettingsProvider.notifier)
            .setActiveThemeName('not-a-real-preset');
        final theme = container.read(cruxColorThemeProvider);
        expect(theme.id, 'crux-dark');
      },
    );

    test(
      "merges persisted themeOverrides onto the base preset's tokens",
      () {
        container.read(appSettingsProvider.notifier).setThemeOverrides({
          'canvas.background': '#112233',
        });
        final theme = container.read(cruxColorThemeProvider);
        expect(theme.id, 'crux-dark');
        expect(
          theme.color('canvas', 'background'),
          const Color(0xFF112233),
        );
      },
    );

    test(
      'ignores unparseable override entries and falls back to the base '
      'preset unchanged',
      () {
        container.read(appSettingsProvider.notifier).setThemeOverrides({
          'canvas.background': 'not-a-color',
        });
        final theme = container.read(cruxColorThemeProvider);
        final base = builtinPresets()['crux-dark']!;
        expect(
          theme.color('canvas', 'background'),
          base.color('canvas', 'background'),
        );
      },
    );
  });

  group('LintcruxCruxColorThemeNotifier.activate', () {
    test(
      "persists the activated preset's id and clears overrides when it "
      'is a builtin preset',
      () {
        // Seed a stale override so the test proves it gets cleared, not
        // just left empty by coincidence.
        container.read(appSettingsProvider.notifier).setThemeOverrides({
          'canvas.background': '#112233',
        });
        final lightPreset = builtinPresets()['crux-light']!;

        container.read(cruxColorThemeProvider.notifier).activate(lightPreset);

        final settings = container.read(appSettingsProvider);
        expect(settings.core.activeThemeName, 'crux-light');
        expect(settings.core.themeOverrides, isEmpty);
        expect(container.read(cruxColorThemeProvider).id, 'crux-light');
      },
    );
  });

  group('LintcruxCruxColorThemeNotifier.applyOverrides', () {
    test(
      'layers the override onto the active theme AND persists the '
      'dotted-id diff back onto AppSettings',
      () {
        container.read(cruxColorThemeProvider.notifier).applyOverrides({
          'canvas.background': const Color(0xFF445566),
        });

        final theme = container.read(cruxColorThemeProvider);
        expect(theme.color('canvas', 'background'), const Color(0xFF445566));

        final settings = container.read(appSettingsProvider);
        expect(settings.core.activeThemeName, 'crux-dark');
        expect(
          settings.core.themeOverrides['canvas.background'],
          '#445566',
        );
      },
    );

    test('an empty override map is a no-op — no persistence write', () {
      container.read(cruxColorThemeProvider.notifier).applyOverrides({});
      final settings = container.read(appSettingsProvider);
      // Untouched: still the AppSettings() constructor default.
      expect(settings.core.themeOverrides, isEmpty);
      expect(settings.core.activeThemeName, 'crux-dark');
    });
  });
}
