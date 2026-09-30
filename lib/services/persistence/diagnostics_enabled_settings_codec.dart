// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `SharedPreferences` codec for the Settings → General "Enable diagnostics"
/// preference, the release-build opt-in for the Tab Diagnostics drawer and
/// the App Diagnostics dialog.
///
/// A [SettingsCodec] over the single `bool`, for the reason
/// `AutoUpdateCheckSettingsCodec` gives: open core persists settings field by
/// field, so a whole-model codec would claim to persist fields nothing
/// writes.
///
/// The key is `CoreSettingsCodec`'s own, so a later whole-model codec adopts
/// the stored value without a migration.
class DiagnosticsEnabledSettingsCodec implements SettingsCodec<bool> {
  /// Const constructor — the codec is stateless.
  const DiagnosticsEnabledSettingsCodec();

  /// `SharedPreferences` key holding the persisted toggle.
  static const String prefsKey = 'settings.diagnosticsEnabled';

  /// The value used when nothing has been persisted yet: off, matching
  /// `CoreSettings.diagnosticsEnabled` in every suite product.
  static const bool defaultValue = false;

  @override
  Future<bool> load(SharedPreferences prefs) async {
    try {
      return prefs.getBool(prefsKey) ?? defaultValue;
    } on Object {
      // A value of the wrong type under the key; see
      // `AutoUpdateCheckSettingsCodec.load`.
      return defaultValue;
    }
  }

  @override
  Future<void> save(SharedPreferences prefs, bool settings) async {
    await prefs.setBool(prefsKey, settings);
  }
}
