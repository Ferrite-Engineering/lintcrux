// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/services/persistence/auto_update_check_settings_codec.dart';

/// The [SettingsService] that reads and writes the Settings → General
/// "Automatically check for updates" preference.
///
/// Override in tests with a `SettingsService(codec, prefsOverride: prefs)` so
/// the round trip runs against `SharedPreferences.setMockInitialValues` rather
/// than the platform plugin.
final Provider<SettingsService<bool>> autoUpdateCheckSettingsServiceProvider =
    Provider<SettingsService<bool>>(
      (_) => const SettingsService<bool>(AutoUpdateCheckSettingsCodec()),
      name: 'autoUpdateCheckSettingsServiceProvider',
    );
