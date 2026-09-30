// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/named_filter_preset.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';
import 'package:lintcrux/features/violations/models/saved_filter_presets_state.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/project/project_file_codec.dart';

/// Owns the tab's saved filter presets and the currently active preset.
///
/// The presets are the open project's `filterPresets`: they are read from
/// the `.lintcrux` file when the project opens, and [save] / [delete]
/// write the change back to that file (through
/// [CurrentProjectNotifier.updateProjectFile]), so a preset survives
/// closing the tab and is shared with everyone who opens the project.
/// With no project loaded — the SARIF viewers — presets live for the
/// session only.
///
/// Activating a preset additionally applies its filter dimensions to
/// [violationTableStateProvider] so the table immediately re-filters.
class SavedFilterPresetsNotifier extends Notifier<SavedFilterPresetsState> {
  /// The active preset name, kept across rebuilds: a project change (a
  /// severity override, a saved preset) rebuilds this notifier, and that
  /// must not drop the user's selection.
  String? _activeName;

  Future<void> _persisted = Future<void>.value();

  /// Completes when the most recent [save] or [delete] has been written to
  /// the project file, or with a [ProjectFileException] when it could not
  /// be — so the caller can report a preset that was not saved.
  Future<void> get persisted => _persisted;

  @override
  SavedFilterPresetsState build() {
    final presets =
        ref.watch(currentProjectProvider.select((p) => p?.filterPresets)) ??
        const <NamedFilterPreset>[];
    final active = _activeName;
    final keepActive = active != null && presets.any((p) => p.name == active);
    if (!keepActive) _activeName = null;
    return SavedFilterPresetsState(
      presets: List<NamedFilterPreset>.unmodifiable(presets),
      activePresetName: keepActive ? active : null,
    );
  }

  /// Replaces the entire state. Used by bootstrap / project-load to seed
  /// the notifier from persisted state. Treats identical input as a
  /// no-op to avoid spurious rebuilds.
  void replace(SavedFilterPresetsState next) {
    if (state == next) return;
    _activeName = next.activePresetName;
    state = next;
  }

  /// Adds a new preset (or replaces an existing one with the same name).
  /// Does not change the active selection unless the saved name matches
  /// the active one (in which case the active is naturally re-resolved).
  void save(NamedFilterPreset preset) {
    final without = state.presets.where((p) => p.name != preset.name);
    final next = <NamedFilterPreset>[...without, preset];
    state = state.copyWith(presets: List.unmodifiable(next));
    _persist(next);
  }

  /// Removes the preset with [name]. If the deleted preset was active,
  /// the active selection is cleared.
  void delete(String name) {
    final next = state.presets
        .where((p) => p.name != name)
        .toList(growable: false);
    final clearActive = state.activePresetName == name;
    if (clearActive) _activeName = null;
    state = state.copyWith(
      presets: List.unmodifiable(next),
      clearActivePreset: clearActive,
    );
    _persist(next);
  }

  /// Writes [presets] to the open project, in memory and in its file.
  void _persist(List<NamedFilterPreset> presets) {
    if (ref.read(currentProjectProvider) == null) return;
    final unmodifiable = List<NamedFilterPreset>.unmodifiable(presets);
    final projectNotifier = ref.read(currentProjectProvider.notifier)
      ..setFilterPresets(unmodifiable);
    _persisted = projectNotifier.updateProjectFile(
      (authored) => authored.copyWith(filterPresets: unmodifiable),
    );
  }

  /// Activates the preset with [name] (or deactivates by passing
  /// `null`). When activating, the matching preset's filter dimensions
  /// are pushed into [violationTableStateProvider] so the table updates
  /// immediately.
  void activate(String? name) {
    if (name == null) {
      _activeName = null;
      state = state.copyWith(clearActivePreset: true);
      return;
    }
    NamedFilterPreset? match;
    for (final p in state.presets) {
      if (p.name == name) {
        match = p;
        break;
      }
    }
    if (match == null) return;
    _activeName = name;
    state = state.copyWith(activePresetName: name);
    // Apply to the table immediately. The user can still manually tweak
    // filters after activation (the active-preset selection persists,
    // but the table state diverges from it — the dropdown should reflect
    // this via the controller wiring at the UI layer).
    ref.read(violationTableStateProvider.notifier).applyFromPreset(match);
  }
}

/// Provider exposing the saved-filter-presets state.
final NotifierProvider<SavedFilterPresetsNotifier, SavedFilterPresetsState>
savedFilterPresetsProvider =
    NotifierProvider<SavedFilterPresetsNotifier, SavedFilterPresetsState>(
      SavedFilterPresetsNotifier.new,
    );

/// Helper extension that materializes a [NamedFilterPreset] from the
/// current [ViolationTableState]. The "name" is supplied by the user via
/// the save dialog at call time, so this helper takes it as a parameter.
extension ViolationTableStateToPreset on ViolationTableState {
  /// Returns a [NamedFilterPreset] capturing the active filters of this
  /// state under the user-chosen [name].
  NamedFilterPreset toPreset(String name) {
    return NamedFilterPreset(
      name: name,
      severities: Set.unmodifiable(severities),
      engineIds: Set.unmodifiable(engineIds),
      ruleSubstring: ruleSubstring,
      fileGlob: fileGlob,
    );
  }
}
