// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/enums/violation_view_mode.dart';
import 'package:lintcrux/domain/models/filter_preset.dart';

/// Reserved id of the "All Violations" built-in preset. Empty
/// filterState (no dimensions, no view-mode override).
const String kBuiltinAllViolationsPresetId = 'builtin_all_violations';

/// Reserved id of the "Errors Only" built-in preset. `severities`
/// includes [Severity.fatal] and [Severity.error]; no view-mode
/// override.
const String kBuiltinErrorsOnlyPresetId = 'builtin_errors_only';

/// Reserved id of the "New Violations" built-in preset. `viewMode`
/// set to [ViolationViewMode.onlyNew]; falls back gracefully to
/// "All Violations" semantics in `visibleViolationsProvider` when no
/// baseline is active.
const String kBuiltinNewViolationsPresetId = 'builtin_new_violations';

/// Stable sentinel timestamp used for built-in `createdAt` / `updatedAt`
/// so the JSON form of a built-in does not depend on when the user
/// first saw it (matches the "Git short SHA"-style determinism the
/// baseline subsystem uses).
final DateTime _builtinStableTimestamp = DateTime.utc(2024);

/// The canonical list of built-in filter presets shipped by open-core.
///
/// Declared in the open core next to the [FilterPreset] model they
/// instantiate. The surfaces that list them — the Pro overlay's preset
/// selector and manager — are the only readers; the open core's own
/// Filter preset dropdown lists the project's `NamedFilterPreset`s instead.
///
/// Sort order convention: built-ins occupy the `0`–`99` range so they
/// always come first in dropdowns; user-authored presets default to
/// `100+` (assigned by [JsonFileFilterPresetStore]).
///
/// Each call returns a fresh list so callers that intend to mutate
/// (e.g. tests that prepend a custom built-in) do not corrupt the
/// shared list.
List<FilterPreset> builtinFilterPresets() {
  return <FilterPreset>[
    FilterPreset(
      id: kBuiltinAllViolationsPresetId,
      name: 'All Violations',
      builtin: true,
      filterState: const <String, Object?>{},
      createdAt: _builtinStableTimestamp,
      updatedAt: _builtinStableTimestamp,
    ),
    FilterPreset(
      id: kBuiltinErrorsOnlyPresetId,
      name: 'Errors Only',
      builtin: true,
      sortOrder: 10,
      filterState: const <String, Object?>{
        'severities': <String>['fatal', 'error'],
      },
      createdAt: _builtinStableTimestamp,
      updatedAt: _builtinStableTimestamp,
    ),
    FilterPreset(
      id: kBuiltinNewViolationsPresetId,
      name: 'New Violations',
      builtin: true,
      sortOrder: 20,
      filterState: const <String, Object?>{
        'viewMode': 'onlyNew',
      },
      createdAt: _builtinStableTimestamp,
      updatedAt: _builtinStableTimestamp,
    ),
  ];
}

/// `true` if [presetId] matches one of the three shipped built-ins.
/// Used by [JsonFileFilterPresetStore] to refuse mutations and by the
/// manager screen to render the built-in badge / suppress the delete
/// affordance.
bool isBuiltinFilterPresetId(String presetId) {
  return presetId == kBuiltinAllViolationsPresetId ||
      presetId == kBuiltinErrorsOnlyPresetId ||
      presetId == kBuiltinNewViolationsPresetId;
}
