// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/models/filter_preset.dart';

/// Persistence interface for [FilterPreset]s — both the open-core
/// built-ins ("All Violations" / "Errors Only" / "New Violations")
/// and the Pro-overlay-managed user-authored presets.
///
/// Open Core ships [NoopFilterPresetStore] which exposes the three
/// built-ins shipped by `package:lintcrux/services/filter_presets/builtin_presets.dart`
/// and refuses every mutation. The Pro overlay supplies
/// `JsonFileFilterPresetStore` which reads/writes
/// `<project-root>/.lintcrux-filter-presets.json` with schema-
/// versioned content while still exposing the same built-ins at the
/// top of [listAll].
///
/// Distinct from the older `savedFilterPresetsProvider` (which owns the
/// project's `NamedFilterPreset`s, persisted in `LintProject.filterPresets`
/// in the `.lintcrux` file): the two coexist on the violations table. This
/// store is the seam the Pro selector chip / manager screen / built-ins
/// flow through; the older flow is the Filter preset dropdown every tier
/// has.
///
/// Built-ins are non-deletable. Implementations must throw
/// [ArgumentError] from [remove] when asked to remove a built-in;
/// see [JsonFileFilterPresetStore] for the canonical enforcement.
abstract class FilterPresetStore {
  /// Returns all known presets sorted by [FilterPreset.sortOrder]
  /// ascending. Built-ins come first (their sortOrders are reserved
  /// in the `0`–`99` range); user-authored presets follow.
  Future<List<FilterPreset>> listAll();

  /// Saves [preset] — creates if [preset.id] is unknown, updates
  /// otherwise. Implementations must reject mutations to built-in
  /// presets (matching by id) and reject duplicate names within the
  /// user-authored set.
  ///
  /// The Noop default throws [UnsupportedError]; the Pro overlay
  /// implements the full write path.
  Future<void> addOrUpdate(FilterPreset preset);

  /// Removes the user-authored preset with [presetId]. Throws
  /// [ArgumentError] when [presetId] matches a built-in. The Noop
  /// default throws [UnsupportedError].
  Future<void> remove(String presetId);

  /// Stream that emits on every successful mutation. Used by the
  /// selector chip / manager screen to refresh without polling.
  /// The Noop default returns an empty stream.
  Stream<void> get changed;
}

/// Open-core default that exposes the shipped built-in presets and
/// refuses every mutation.
///
/// The store is constructed with an injected list so tests can
/// substitute a custom built-in set; production code passes the
/// canonical list from `builtinFilterPresets()`.
class NoopFilterPresetStore implements FilterPresetStore {
  /// Creates a [NoopFilterPresetStore] over [builtins].
  const NoopFilterPresetStore({required this.builtins});

  /// The built-in presets exposed via [listAll]. Open-core ships
  /// `builtinFilterPresets()`; tests may pass a smaller list.
  final List<FilterPreset> builtins;

  @override
  Future<List<FilterPreset>> listAll() async {
    return List<FilterPreset>.unmodifiable(builtins);
  }

  @override
  Future<void> addOrUpdate(FilterPreset preset) {
    throw UnsupportedError(
      'NoopFilterPresetStore.addOrUpdate is unavailable on the open-core '
      'tier — user-authored filter preset persistence is a Pro feature.',
    );
  }

  @override
  Future<void> remove(String presetId) {
    throw UnsupportedError(
      'NoopFilterPresetStore.remove is unavailable on the open-core '
      'tier — user-authored filter preset persistence is a Pro feature.',
    );
  }

  @override
  Stream<void> get changed => const Stream<void>.empty();
}
