// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/interfaces/filter_preset_store.dart';
import 'package:lintcrux/services/filter_presets/builtin_presets.dart';

/// Open-core extension point through which the Pro overlay
/// contributes a Pro-grade [FilterPresetStore] implementation.
///
/// The default is [NoopFilterPresetStore] seeded with the canonical
/// `builtinFilterPresets()` list ("All Violations" / "Errors Only" / "New
/// Violations"). Nothing in the open core reads this provider: the only
/// surfaces that list presets from it — the selector chip and the manager
/// screen — are Pro overlay code, so the built-ins appear only there.
///
/// The Pro overlay's `proOverrides` replaces this provider with one
/// that returns a `JsonFileFilterPresetStore` (reading / writing
/// `<project-root>/.lintcrux-filter-presets.json` with built-in
/// protection enforced).
final Provider<FilterPresetStore> filterPresetStoreProvider =
    Provider<FilterPresetStore>(
      (_) => NoopFilterPresetStore(builtins: builtinFilterPresets()),
    );
