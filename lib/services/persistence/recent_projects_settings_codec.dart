// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `SharedPreferences` codec for the welcome screen's Recent projects list:
/// absolute `.lintcrux` paths, most recent first.
class RecentProjectsSettingsCodec implements SettingsCodec<List<String>> {
  /// Const constructor — the codec is stateless.
  const RecentProjectsSettingsCodec();

  /// `SharedPreferences` key holding the list.
  static const String prefsKey = 'settings.lintcrux.recentProjects';

  @override
  Future<List<String>> load(SharedPreferences prefs) async {
    try {
      return List<String>.unmodifiable(
        prefs.getStringList(prefsKey) ?? const <String>[],
      );
    } on Object {
      // A value of the wrong type under the key. An empty list is the only
      // safe reading, and a corrupt preference must not fail a launch.
      return const <String>[];
    }
  }

  @override
  Future<void> save(SharedPreferences prefs, List<String> settings) async {
    await prefs.setStringList(prefsKey, settings);
  }
}
