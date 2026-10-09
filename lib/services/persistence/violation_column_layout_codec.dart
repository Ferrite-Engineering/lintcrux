// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_settings/crux_settings.dart';
import 'package:lintcrux/domain/models/violation_column_layout.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `SharedPreferences` codec for the violation table's column widths.
///
/// Stored as one JSON object of column name to weight. A column missing or
/// unreadable in it takes its default; the others keep theirs.
class ViolationColumnLayoutCodec
    implements SettingsCodec<ViolationColumnLayout> {
  /// Const constructor — the codec is stateless.
  const ViolationColumnLayoutCodec();

  /// `SharedPreferences` key holding the JSON object.
  static const String prefsKey = 'settings.violationColumnWeights';

  @override
  Future<ViolationColumnLayout> load(SharedPreferences prefs) async {
    final raw = prefs.get(prefsKey);
    if (raw is! String) return ViolationColumnLayout.defaults;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return ViolationColumnLayout.defaults;
    }
    if (decoded is! Map<String, Object?>) {
      return ViolationColumnLayout.defaults;
    }
    return ViolationColumnLayout({
      for (final column in ViolationTableColumn.values)
        if (decoded[column.name] case final num weight)
          column: weight.toDouble(),
    });
  }

  @override
  Future<void> save(SharedPreferences prefs, ViolationColumnLayout settings) =>
      prefs.setString(
        prefsKey,
        jsonEncode({
          for (final entry in settings.weights.entries)
            entry.key.name: entry.value,
        }),
      );
}
