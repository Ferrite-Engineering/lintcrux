// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_settings/crux_settings.dart';
import 'package:lintcrux/domain/models/engine_binary_override.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `SharedPreferences` codec for Settings > Engines > Engine binary paths:
/// the per-engine Auto-detect / Bundled / Custom choice and a Custom path.
///
/// Stored as one JSON object under [prefsKey], keyed by engine id:
///
/// ```json
/// {"verilator": {"source": "custom", "path": "/opt/verilator/bin/verilator"}}
/// ```
///
/// Auto-detect entries are never stored (`AppSettingsNotifier` removes them),
/// so an empty map is the default. A value the codec cannot read — hand-edited
/// preferences, an engine source this build does not know — is dropped entry
/// by entry rather than failing the whole map, so one bad row cannot cost the
/// user every other engine's path.
class EngineBinaryOverridesSettingsCodec
    implements SettingsCodec<Map<String, EngineBinaryOverride>> {
  /// Const constructor — the codec is stateless.
  const EngineBinaryOverridesSettingsCodec();

  /// `SharedPreferences` key holding the JSON-encoded override map.
  static const String prefsKey = 'settings.lintcrux.engineBinaryOverrides';

  @override
  Future<Map<String, EngineBinaryOverride>> load(
    SharedPreferences prefs,
  ) async {
    final Object? raw;
    try {
      raw = prefs.getString(prefsKey);
    } on Object {
      return const <String, EngineBinaryOverride>{};
    }
    if (raw is! String || raw.isEmpty) {
      return const <String, EngineBinaryOverride>{};
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const <String, EngineBinaryOverride>{};
    }
    if (decoded is! Map<String, dynamic>) {
      return const <String, EngineBinaryOverride>{};
    }
    final overrides = <String, EngineBinaryOverride>{};
    for (final entry in decoded.entries) {
      final value = entry.value;
      if (value is! Map<String, dynamic>) continue;
      final source = EngineBinarySource.values
          .where((s) => s.name == value['source'])
          .firstOrNull;
      if (source == null) continue;
      final path = value['path'];
      overrides[entry.key] = EngineBinaryOverride(
        source: source,
        path: path is String && path.isNotEmpty ? path : null,
      );
    }
    return Map<String, EngineBinaryOverride>.unmodifiable(overrides);
  }

  @override
  Future<void> save(
    SharedPreferences prefs,
    Map<String, EngineBinaryOverride> settings,
  ) async {
    await prefs.setString(
      prefsKey,
      jsonEncode(<String, Object?>{
        for (final entry in settings.entries)
          entry.key: <String, Object?>{
            'source': entry.value.source.name,
            if (entry.value.path != null) 'path': entry.value.path,
          },
      }),
    );
  }
}
