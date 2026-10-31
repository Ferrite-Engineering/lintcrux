// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:lintcrux/domain/enums/elaboration_time_limit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `SharedPreferences` codec for the Settings → Engines "Yosys time limit"
/// preference ([ElaborationTimeLimit]).
///
/// A [SettingsCodec] over the single value, for the reason
/// `AutoUpdateCheckSettingsCodec` gives: open core persists settings field by
/// field. The value is stored by its enum name; an unknown name (a later
/// build's choice) reads as [ElaborationTimeLimit.automatic].
class ElaborationTimeLimitSettingsCodec
    implements SettingsCodec<ElaborationTimeLimit> {
  /// Const constructor — the codec is stateless.
  const ElaborationTimeLimitSettingsCodec();

  /// `SharedPreferences` key holding the persisted choice.
  static const String prefsKey = 'settings.lintcrux.elaborationTimeLimit';

  /// The value used when nothing has been persisted yet.
  static const ElaborationTimeLimit defaultValue =
      ElaborationTimeLimit.automatic;

  @override
  Future<ElaborationTimeLimit> load(SharedPreferences prefs) async {
    final String? name;
    try {
      name = prefs.getString(prefsKey);
    } on Object {
      // A value of the wrong type under the key; see
      // `AutoUpdateCheckSettingsCodec.load`.
      return defaultValue;
    }
    for (final limit in ElaborationTimeLimit.values) {
      if (limit.name == name) return limit;
    }
    return defaultValue;
  }

  @override
  Future<void> save(SharedPreferences prefs, ElaborationTimeLimit settings) =>
      prefs.setString(prefsKey, settings.name);
}
