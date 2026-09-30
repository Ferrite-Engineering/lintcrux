// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/engine_binary_override.dart';
import 'package:lintcrux/services/persistence/engine_binary_overrides_settings_codec.dart';

/// The [SettingsService] that reads and writes Settings > Engines > Engine
/// binary paths.
///
/// Override in tests with a `SettingsService(codec, prefsOverride: prefs)` so
/// the round trip runs against `SharedPreferences.setMockInitialValues` rather
/// than the platform plugin.
final Provider<SettingsService<Map<String, EngineBinaryOverride>>>
engineBinaryOverridesSettingsServiceProvider =
    Provider<SettingsService<Map<String, EngineBinaryOverride>>>(
      (_) => const SettingsService<Map<String, EngineBinaryOverride>>(
        EngineBinaryOverridesSettingsCodec(),
      ),
      name: 'engineBinaryOverridesSettingsServiceProvider',
    );

/// The engine binary overrides persisted when this launch started.
///
/// Seeds `appSettingsProvider` **synchronously**. The overrides decide which
/// binary the first run starts, and a restored tab runs its engines as soon
/// as it opens — an asynchronous restore would race that first run and lint
/// it with the `PATH` binaries the user configured away from. `bootstrap`
/// resolves [loadEngineBinaryOverrides] once, before `runApp`, and overrides
/// this with the answer; tests get the empty default with no storage call,
/// for the same reason `launchRestoreDecisionProvider` is shaped this way.
final Provider<Map<String, EngineBinaryOverride>>
launchEngineBinaryOverridesProvider =
    Provider<Map<String, EngineBinaryOverride>>(
      (_) => const <String, EngineBinaryOverride>{},
      name: 'launchEngineBinaryOverridesProvider',
    );

/// Loads the persisted engine binary overrides, or none on any failure.
///
/// A failure means no preferences backend; starting with Auto-detect for
/// every engine is the only safe reading of that.
///
/// [service] is injectable for tests; production passes nothing.
Future<Map<String, EngineBinaryOverride>> loadEngineBinaryOverrides({
  SettingsService<Map<String, EngineBinaryOverride>>? service,
}) async {
  try {
    return await (service ??
            const SettingsService<Map<String, EngineBinaryOverride>>(
              EngineBinaryOverridesSettingsCodec(),
            ))
        .load();
  } on Object {
    return const <String, EngineBinaryOverride>{};
  }
}
