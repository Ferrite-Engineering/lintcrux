// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/core/platform/web_mode.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/services/engines/engine_binary_ids.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';

/// Detected version string per registered engine id, e.g.
/// `{'verilator': 'Verilator 5.022 …', 'verible': 'v0.0-3752-…'}`.
///
/// Probes every engine in [engineRegistryProvider] by running its
/// `detectVersion` against the binary the user configured in Settings →
/// Engines (auto-detect / bundled / custom). An engine whose binary is absent
/// from `PATH`, refuses to run, or prints nothing usable is simply **omitted**
/// from the map — an unavailable engine is a normal state on a machine that
/// installed only some of the six, not an error.
///
/// The probe spawns one short-lived subprocess per engine, so it is
/// deliberately *not* watched by any always-on surface. Callers that need the
/// versions (the beta issue reporter's Session State contributor) await this
/// future once, immediately before they need it; the resolved value is then
/// cached for the container's lifetime.
///
/// Root-scoped on purpose: both inputs are root state (the engine registry and
/// the user-wide binary overrides), so two tabs probing the same six binaries
/// would be pure waste.
///
/// In the browser nothing is probed: the web viewer runs no engines, and a
/// probe would reach `dart:io` platform state the browser does not have
/// (the Yosys availability probe reads `Platform.isWindows`). The issue
/// reporter is reachable from the web command palette, so the guard is
/// here rather than trusted to every caller; see
/// [engineVersionProbingSupportedProvider].
final FutureProvider<Map<String, String>> engineVersionsProvider =
    FutureProvider<Map<String, String>>((ref) async {
      if (!ref.watch(engineVersionProbingSupportedProvider)) {
        return const <String, String>{};
      }
      final registry = ref.watch(engineRegistryProvider);
      final settings = ref.watch(appSettingsProvider);

      final versions = <String, String>{};
      for (final engine in registry.engines) {
        final config = settings
            .engineBinaryOverrideFor(binaryEngineIdFor(engine.id))
            .toEngineBinaryConfig();
        String? detected;
        try {
          detected = await engine.detectVersion(config);
        } on Object {
          detected = null;
        }
        if (detected == null) continue;
        final trimmed = detected.trim();
        if (trimmed.isEmpty) continue;
        versions[engine.id] = trimmed;
      }
      return Map<String, String>.unmodifiable(versions);
    }, name: 'engineVersionsProvider');

/// Whether engine binaries can be probed on this platform: false in the
/// browser. A provider rather than a bare `isWebMode` check so a VM test can
/// run the web branch.
final Provider<bool> engineVersionProbingSupportedProvider = Provider<bool>(
  (_) => !isWebMode,
  name: 'engineVersionProbingSupportedProvider',
);
