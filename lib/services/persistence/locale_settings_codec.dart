// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `SharedPreferences` codec for the Settings → Appearance "Language"
/// preference.
///
/// A [SettingsCodec] over the single locale tag rather than over the whole
/// `AppSettings` record, for the reason spelled out in
/// `AutoUpdateCheckSettingsCodec`: LintCrux's `appSettingsProvider` is an
/// in-memory notifier and open-core does not round-trip the full settings
/// model, so a whole-model codec would claim to persist fields nothing
/// writes.
///
/// [prefsKey] deliberately matches `CoreSettingsCodec`'s key for the same
/// field, so a later whole-model codec adopts the stored value verbatim.
class LocaleSettingsCodec implements SettingsCodec<String> {
  /// Const constructor — the codec is stateless.
  const LocaleSettingsCodec();

  /// `SharedPreferences` key holding the persisted locale tag. Shared with
  /// `CoreSettingsCodec`.
  static const String prefsKey = 'settings.locale';

  /// The value used when nothing has been persisted yet — English, the
  /// suite default (`CoreSettings.defaults()`).
  static const String defaultValue = 'en';

  @override
  Future<String> load(SharedPreferences prefs) async {
    try {
      return prefs.getString(prefsKey) ?? defaultValue;
    } on Object {
      // A value of the wrong type under the key — hand-edited preferences,
      // or a future schema change that reused it. Falling back keeps a
      // corrupt preference from turning into a launch failure.
      return defaultValue;
    }
  }

  @override
  Future<void> save(SharedPreferences prefs, String settings) async {
    await prefs.setString(prefsKey, settings);
  }
}
