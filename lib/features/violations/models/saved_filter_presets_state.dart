// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/models/named_filter_preset.dart';
import 'package:meta/meta.dart';

/// In-memory state of the saved-filter-presets system.
///
/// Holds the user-visible list of [presets] and the name of the
/// currently activated preset (`null` = no preset, the user's filters
/// are whatever they have manually applied). The provider that owns
/// this state reads the presets from the open project's `.lintcrux`.
@immutable
class SavedFilterPresetsState {
  /// Creates a [SavedFilterPresetsState].
  const SavedFilterPresetsState({
    this.presets = const <NamedFilterPreset>[],
    this.activePresetName,
  });

  /// Empty initial state — no presets saved, no active preset.
  static const SavedFilterPresetsState empty = SavedFilterPresetsState();

  /// Ordered list of presets visible to the user, in the order they were
  /// saved.
  final List<NamedFilterPreset> presets;

  /// Currently active preset name; `null` when no preset is active.
  /// Tracking by name (rather than by index) keeps the active selection
  /// stable across reorderings and across the per-project vs. user-wide
  /// merge.
  final String? activePresetName;

  /// Convenience lookup. Returns `null` if no preset is active or if the
  /// active name doesn't resolve to anything in [presets] (which can
  /// happen briefly after a preset is deleted).
  NamedFilterPreset? get activePreset {
    final name = activePresetName;
    if (name == null) return null;
    for (final p in presets) {
      if (p.name == name) return p;
    }
    return null;
  }

  /// Returns a copy with overridden fields. Pass [activePresetName] as
  /// `''` to explicitly clear it (since `null` is interpreted as "leave
  /// unchanged" by [copyWith]'s convention here).
  SavedFilterPresetsState copyWith({
    List<NamedFilterPreset>? presets,
    String? activePresetName,
    bool clearActivePreset = false,
  }) {
    return SavedFilterPresetsState(
      presets: presets ?? this.presets,
      activePresetName: clearActivePreset
          ? null
          : (activePresetName ?? this.activePresetName),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SavedFilterPresetsState) return false;
    if (other.activePresetName != activePresetName) return false;
    if (other.presets.length != presets.length) return false;
    for (var i = 0; i < presets.length; i++) {
      if (other.presets[i] != presets[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(activePresetName, Object.hashAll(presets));

  @override
  String toString() =>
      'SavedFilterPresetsState(${presets.length} presets, '
      'active: $activePresetName)';
}
