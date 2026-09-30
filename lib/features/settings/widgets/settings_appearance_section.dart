// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/features/settings/widgets/color_theme_section.dart';
import 'package:lintcrux/features/settings/widgets/settings_section_card.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// Settings → Appearance page.
///
/// Hosts the visual preferences:
///
/// - **Color theme presets + import/export** — the suite-shared
///   `ThemeAppearanceSection` from `package:crux_theme`, dropped in via
///   [ColorThemeSection]. Picking a preset (Crux Light/Dark,
///   Solarized Light/Dark, or an installed `.crux-theme.json` pack)
///   flips both Material brightness AND chrome surfaces. Mirrors the
///   WaveCrux / NetCrux reference adoption.
///
/// There is no light/dark/system theme-mode segmented button: brightness
/// follows the active color preset (`themeModeFromBrightness` in
/// `lib/app.dart`), matching the WaveCrux canonical model. The persisted
/// `themeMode` preference and its ARB strings remain for the ⌘⇧K toggle-theme
/// action.
class SettingsAppearanceSection extends ConsumerWidget {
  /// Creates a [SettingsAppearanceSection].
  const SettingsAppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final locale = ref.watch(
      appSettingsProvider.select((s) => s.core.locale),
    );
    // The section's own "Appearance" heading was removed: the dual-pane shell
    // now renders the category title (showDetailTitle: true), so a local
    // heading would duplicate it.
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        SettingsSectionCard(
          children: [
            // The shared suite Language picker — the four shipped locales
            // were unreachable in LintCrux before this (no picker, and the
            // persisted CoreSettings.locale was never applied).
            CruxLocaleSettingTile(
              label: l10n.settingsLanguageLabel,
              description: l10n.settingsLanguageDescription,
              locale: locale,
              onChanged: (v) =>
                  ref.read(appSettingsProvider.notifier).setLocale(v),
            ),
            // Suite-shared color-theme presets + import/export. Composes the
            // individual `crux_theme` widgets (see [ColorThemeSection]) and
            // bridges activation into `cruxColorThemeProvider`, which writes
            // preset selection back to `AppSettings.core.activeThemeName` /
            // `themeOverrides` via the LintCrux notifier override.
            const ColorThemeSection(),
          ],
        ),
      ],
    );
  }
}
