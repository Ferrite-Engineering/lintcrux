// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/services/persistence/cxp_settings_codec.dart';

/// The [SettingsService] that reads and writes Settings → CXP Cross-Probe.
///
/// Override in tests with a `SettingsService(codec, prefsOverride: prefs)` so
/// the round trip runs against `SharedPreferences.setMockInitialValues` rather
/// than the platform plugin.
final Provider<SettingsService<CxpSettings>> cxpSettingsServiceProvider =
    Provider<SettingsService<CxpSettings>>(
      (_) => const SettingsService<CxpSettings>(CxpSettingsCodec()),
      name: 'cxpSettingsServiceProvider',
    );

/// The CXP preferences persisted when this launch started.
///
/// Seeds `appSettingsProvider` **synchronously**, for the reason
/// `launchEngineBinaryOverridesProvider` gives: the CXP server lifecycle
/// starts from the first settings value it sees. An asynchronous restore
/// would start the server on the default (enabled), write its discovery
/// manifest so peers see it, then stop it a moment later — the opposite of
/// what a user who turned CXP off asked for. `bootstrap` resolves
/// [loadCxpSettings] once, before `runApp`, and overrides this with the
/// answer; tests get the defaults with no storage call.
final Provider<CxpSettings> launchCxpSettingsProvider = Provider<CxpSettings>(
  (_) => const CxpSettings(),
  name: 'launchCxpSettingsProvider',
);

/// Loads the persisted CXP preferences, or the defaults on any failure.
///
/// A failure means no preferences backend; the defaults are what every
/// launch used before these settings were persisted.
///
/// [service] is injectable for tests; production passes nothing.
Future<CxpSettings> loadCxpSettings({
  SettingsService<CxpSettings>? service,
}) async {
  try {
    return await (service ??
            const SettingsService<CxpSettings>(CxpSettingsCodec()))
        .load();
  } on Object {
    return const CxpSettings();
  }
}
