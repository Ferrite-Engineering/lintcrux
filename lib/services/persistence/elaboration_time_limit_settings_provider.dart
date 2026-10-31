// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/enums/elaboration_time_limit.dart';
import 'package:lintcrux/services/persistence/elaboration_time_limit_settings_codec.dart';

/// The [SettingsService] that reads and writes the Settings → Engines
/// "Yosys time limit" preference.
///
/// Override in tests with a `SettingsService(codec, prefsOverride: prefs)` so
/// the round trip runs against `SharedPreferences.setMockInitialValues` rather
/// than the platform plugin.
final Provider<SettingsService<ElaborationTimeLimit>>
elaborationTimeLimitSettingsServiceProvider =
    Provider<SettingsService<ElaborationTimeLimit>>(
      (_) => const SettingsService<ElaborationTimeLimit>(
        ElaborationTimeLimitSettingsCodec(),
      ),
      name: 'elaborationTimeLimitSettingsServiceProvider',
    );
