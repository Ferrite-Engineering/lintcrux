// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `SharedPreferences` codec for the Settings → General "Restore tabs on
/// launch" preference.
///
/// A [SettingsCodec] over the single `bool` rather than over the whole
/// [AppSettings] record, for the reason spelled out in
/// [AutoUpdateCheckSettingsCodec]: LintCrux's `appSettingsProvider` is an
/// in-memory notifier and open-core does not round-trip the full settings
/// model, so a whole-model codec would claim to persist fields nothing
/// writes.
///
/// [prefsKey] deliberately matches `CoreSettingsCodec`'s key for the same
/// field, so a later whole-model codec adopts the stored value verbatim —
/// and so the value a user already set by hand (`defaults write
/// com.ferriteengineering.lintcruxPro flutter.settings.restoreTabsOnLaunch
/// -bool false`, `SharedPreferences` namespacing the key under `flutter.`)
/// is the one this reads.
class RestoreTabsSettingsCodec implements SettingsCodec<bool> {
  /// Const constructor — the codec is stateless.
  const RestoreTabsSettingsCodec();

  /// `SharedPreferences` key holding the persisted toggle. Shared with
  /// `CoreSettingsCodec`.
  static const String prefsKey = 'settings.restoreTabsOnLaunch';

  /// The value used when nothing has been persisted yet.
  ///
  /// `true` — restoring the previous session is the behavior LintCrux has
  /// always had, and this preference exists for the users who want it off,
  /// not to change what happens for everyone else. It is also the safer
  /// default under a read failure: a session silently dropped because a
  /// *preference* could not be read is the worse of the two mistakes.
  static const bool defaultValue = true;

  @override
  Future<bool> load(SharedPreferences prefs) async {
    try {
      return prefs.getBool(prefsKey) ?? defaultValue;
    } on Object {
      // A value of the wrong type under the key — hand-edited preferences,
      // or a future schema change that reused it. `getBool` throws on a type
      // mismatch; falling back keeps a corrupt preference from turning into
      // a launch failure, matching how `CoreSettingsCodec` treats every
      // malformed field.
      return defaultValue;
    }
  }

  @override
  Future<void> save(SharedPreferences prefs, bool settings) async {
    await prefs.setBool(prefsKey, settings);
  }
}
