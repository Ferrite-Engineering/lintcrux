// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `SharedPreferences` codec for the Settings → General
/// "Automatically check for updates" preference.
///
/// A [SettingsCodec] over the single `bool` rather than over the whole
/// [AppSettings] record: LintCrux's `appSettingsProvider` is an in-memory
/// notifier and open-core does not yet round-trip the full settings model
/// through `crux_settings`, so a whole-model codec would claim to persist
/// fields (panel layout, engine binary overrides, recent projects) that
/// nothing writes. Persisting exactly the field the update mechanism owns
/// keeps the claim true.
///
/// The key is namespaced under `settings.` to match `CoreSettingsCodec`, so a
/// later whole-model codec can adopt it verbatim without migrating any user's
/// stored value.
class AutoUpdateCheckSettingsCodec implements SettingsCodec<bool> {
  /// Const constructor — the codec is stateless.
  const AutoUpdateCheckSettingsCodec();

  /// `SharedPreferences` key holding the persisted toggle.
  static const String prefsKey = 'settings.autoCheckForUpdates';

  /// The value used when nothing has been persisted yet: automatic checks are
  /// on, matching the suite-wide default in `crux_updates`.
  static const bool defaultValue = true;

  @override
  Future<bool> load(SharedPreferences prefs) async {
    try {
      return prefs.getBool(prefsKey) ?? defaultValue;
    } on Object {
      // A value of the wrong type under the key — a hand-edited preferences
      // file, or a future schema change that reused it. `getBool` throws on a
      // type mismatch; falling back keeps a corrupt preference from turning
      // into a launch failure, matching how `CoreSettingsCodec` treats every
      // malformed field.
      return defaultValue;
    }
  }

  @override
  Future<void> save(SharedPreferences prefs, bool settings) async {
    await prefs.setBool(prefsKey, settings);
  }
}
