// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/services/persistence/locale_settings_codec.dart';

/// The [SettingsService] that reads and writes the Settings → Appearance
/// "Language" preference.
///
/// Override in tests with a `SettingsService(codec, prefsOverride: prefs)`
/// so the round trip runs against `SharedPreferences.setMockInitialValues`
/// rather than the platform plugin.
final Provider<SettingsService<String>> localeSettingsServiceProvider =
    Provider<SettingsService<String>>(
      (_) => const SettingsService<String>(LocaleSettingsCodec()),
      name: 'localeSettingsServiceProvider',
    );
