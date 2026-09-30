// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';

/// Riverpod override that wires LintCrux persistence into `crux_theme`'s
/// `cruxColorThemeProvider`. Mirrors the WaveCrux / NetCrux reference
/// notifiers so the suite presents a uniform theming surface across all
/// four apps — preset selection writes back to
/// `AppSettings.core.activeThemeName` / `core.themeOverrides`, and the
/// in-memory theme rebuilds from those settings whenever the app boots.
///
/// LintCrux's `appSettingsProvider` is a **synchronous** `Notifier<
/// AppSettings>` (not the `AsyncNotifier` shape WaveCrux / NetCrux use),
/// so this bridge reads its state directly via [ref.watch] instead of
/// going through `.value`. The mutator surface (`setActiveThemeName`,
/// `setThemeOverrides`) is likewise sync; we drive it without `await`.
class LintcruxCruxColorThemeNotifier extends CruxColorThemeNotifier {
  /// Creates a notifier seeded with the suite default (Crux Dark)
  /// built-in preset so reads that race the first settings hydration
  /// still observe a sensible theme. The actual initial preset is
  /// selected by [build] once `appSettingsProvider` has emitted its
  /// first value.
  LintcruxCruxColorThemeNotifier() : super(initial: defaultBuiltinPreset());

  @override
  CruxColorTheme build() {
    final settings = ref.watch(appSettingsProvider);
    // Resolved through `builtinPresetById`, not a raw `presets[...]`
    // lookup, so the retired `wavecrux-dark` / `wavecrux-light` ids that
    // every public-beta user has persisted in `activeThemeName` map onto
    // their `crux-*` replacements instead of silently falling back to
    // the default. A raw map lookup would quietly reset the theme of
    // every user who had chosen Light.
    final base = builtinPresetById(settings.core.activeThemeName) ?? initial;
    if (settings.core.themeOverrides.isEmpty) return base;
    final parsed = _parseOverrides(settings.core.themeOverrides);
    if (parsed.isEmpty) return base;
    return base.mergeTokens(parsed);
  }

  @override
  void activate(CruxColorTheme theme) {
    super.activate(theme);
    _persistDerivedFromTheme(theme);
  }

  @override
  void applyOverrides(Map<String, Color> overrides) {
    if (overrides.isEmpty) return;
    super.applyOverrides(overrides);
    _persistDerivedFromTheme(state);
  }

  void _persistDerivedFromTheme(CruxColorTheme theme) {
    final baseline = builtinPresetById(theme.id);

    final overrides = <String, String>{};
    if (baseline != null) {
      for (final categoryEntry in theme.tokens.entries) {
        final baselineCategory =
            baseline.tokens[categoryEntry.key] ?? const <String, Color>{};
        for (final tokenEntry in categoryEntry.value.entries) {
          final baselineValue = baselineCategory[tokenEntry.key];
          if (baselineValue == null ||
              baselineValue.toARGB32() != tokenEntry.value.toARGB32()) {
            final dotted = CruxColorTheme.dottedId(
              categoryEntry.key,
              tokenEntry.key,
            );
            overrides[dotted] = ThemePackCodec.encodeColor(tokenEntry.value);
          }
        }
      }
    }

    // The notifier's mutators are synchronous (mutate in-memory state
    // immediately). Persistence to `shared_preferences` is wired
    // separately at the bootstrap layer; this bridge is content to
    // update the in-memory snapshot here.
    ref.read(appSettingsProvider.notifier)
      ..setActiveThemeName(theme.id)
      ..setThemeOverrides(overrides);
  }

  static Map<String, Color> _parseOverrides(Map<String, String> raw) {
    final out = <String, Color>{};
    for (final entry in raw.entries) {
      final color = ThemePackCodec.tryParseColor(entry.value);
      if (color != null) out[entry.key] = color;
    }
    return out;
  }
}

/// The single override every LintCrux bootstrap spreads into its
/// [ProviderScope] before `runApp`.
final Override lintcruxCruxColorThemeOverride = cruxColorThemeProvider
    .overrideWith(LintcruxCruxColorThemeNotifier.new);
