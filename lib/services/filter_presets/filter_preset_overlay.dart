// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/enums/violation_view_mode.dart';
import 'package:lintcrux/domain/interfaces/violation_store.dart';
import 'package:lintcrux/domain/models/filter_preset.dart';

/// Result of overlaying a [FilterPreset] on top of a user-supplied
/// [ViolationFilter] and a baseline-aware [ViolationViewMode].
///
/// The overlay produces an *effective* filter (combined AND across
/// every dimension — preset constraints intersect with the user's
/// manual filter controls) and an *effective* view mode (the preset's
/// view-mode wins when present; otherwise the user's view mode passes
/// through unchanged).
class FilterPresetOverlayResult {
  /// Creates a [FilterPresetOverlayResult].
  const FilterPresetOverlayResult({
    required this.effectiveFilter,
    required this.effectiveViewMode,
  });

  /// The combined filter: intersection of the preset's filterState
  /// with the user-supplied [ViolationFilter] from the table state.
  final ViolationFilter effectiveFilter;

  /// The combined view mode: the preset's view-mode wins when present;
  /// otherwise the user-selected view mode passes through.
  final ViolationViewMode effectiveViewMode;
}

/// Pure helper that overlays [preset]'s `filterState` on top of a
/// user-supplied [baseFilter] + [baseViewMode] and returns the
/// effective filter + view mode that `visibleViolationsProvider`
/// should apply.
///
/// Semantics (each dimension):
///
/// * **`severities`** — intersection. If both the preset and the user
///   restrict to a non-empty severity set, only the intersection is
///   kept. If exactly one specifies a set, that set is used. If both
///   are empty, "all severities" remains.
/// * **`engineIds`** — intersection, same shape as severities.
/// * **`ruleSubstring`** — the preset's substring wins when non-empty
///   (a substring filter is single-valued; combining two substrings
///   is not well-defined). When the preset's substring is empty, the
///   user's substring passes through.
/// * **`fileGlob`** — same as ruleSubstring (single-valued; preset
///   wins when non-empty).
/// * **`includeSuppressed`** — `true` when either side enables it
///   (OR — the preset's `showWaived` mirrors the table state's
///   "Show waived" toggle).
/// * **`viewMode`** — the preset's view-mode wins when present;
///   otherwise the user's view mode passes through.
///
/// When [preset] is `null` the function is the identity:
/// `effectiveFilter == baseFilter`, `effectiveViewMode == baseViewMode`.
FilterPresetOverlayResult overlayFilterPreset({
  required FilterPreset? preset,
  required ViolationFilter baseFilter,
  required ViolationViewMode baseViewMode,
}) {
  if (preset == null) {
    return FilterPresetOverlayResult(
      effectiveFilter: baseFilter,
      effectiveViewMode: baseViewMode,
    );
  }
  final state = preset.filterState;

  // Severities — intersection.
  final presetSeverities = _parseSeverityList(state['severities']);
  final combinedSeverities = _intersectOrFallback(
    presetSeverities,
    baseFilter.severities,
  );

  // Engine ids — intersection.
  final presetEngineIds = _parseStringList(state['engineIds']);
  final combinedEngineIds = _intersectOrFallback(
    presetEngineIds,
    baseFilter.engineIds,
  );

  // Substrings / globs — preset wins when non-empty.
  final presetRuleSubstring = state['ruleSubstring'];
  final ruleSubstring =
      (presetRuleSubstring is String && presetRuleSubstring.isNotEmpty)
      ? presetRuleSubstring
      : baseFilter.ruleSubstring;
  final presetFileGlob = state['fileGlob'];
  final fileGlob = (presetFileGlob is String && presetFileGlob.isNotEmpty)
      ? presetFileGlob
      : baseFilter.fileGlob;

  // Suppression — OR.
  final presetShowWaived = state['showWaived'];
  final includeSuppressed =
      baseFilter.includeSuppressed ||
      (presetShowWaived is bool && presetShowWaived);

  // View mode — preset wins when present.
  final presetViewMode = _parseViewMode(state['viewMode']);
  final effectiveViewMode = presetViewMode ?? baseViewMode;

  return FilterPresetOverlayResult(
    effectiveFilter: ViolationFilter(
      severities: combinedSeverities,
      engineIds: combinedEngineIds,
      ruleSubstring: ruleSubstring,
      fileGlob: fileGlob,
      includeSuppressed: includeSuppressed,
    ),
    effectiveViewMode: effectiveViewMode,
  );
}

Set<Severity>? _parseSeverityList(Object? raw) {
  if (raw is! List) return null;
  final out = <Severity>{};
  for (final entry in raw) {
    if (entry is String) {
      final s = _severityFromString(entry);
      if (s != null) out.add(s);
    }
  }
  return out.isEmpty ? null : Set<Severity>.unmodifiable(out);
}

Set<String>? _parseStringList(Object? raw) {
  if (raw is! List) return null;
  final out = <String>{};
  for (final entry in raw) {
    if (entry is String && entry.isNotEmpty) out.add(entry);
  }
  return out.isEmpty ? null : Set<String>.unmodifiable(out);
}

ViolationViewMode? _parseViewMode(Object? raw) {
  if (raw is! String) return null;
  switch (raw) {
    case 'allViolations':
      return ViolationViewMode.allViolations;
    case 'onlyNew':
      return ViolationViewMode.onlyNew;
    case 'onlyResolved':
      return ViolationViewMode.onlyResolved;
    default:
      return null;
  }
}

Set<T>? _intersectOrFallback<T>(Set<T>? presetSet, Set<T>? baseSet) {
  // Both empty / null → no restriction.
  if ((presetSet == null || presetSet.isEmpty) &&
      (baseSet == null || baseSet.isEmpty)) {
    return null;
  }
  if (presetSet == null || presetSet.isEmpty) return baseSet;
  if (baseSet == null || baseSet.isEmpty) return presetSet;
  final intersection = <T>{
    for (final entry in presetSet)
      if (baseSet.contains(entry)) entry,
  };
  // An empty intersection means the user restricted to a set disjoint
  // from the preset's set — surface that exactly (the violations
  // table renders an empty list in that case, which matches the
  // expected behavior).
  return Set<T>.unmodifiable(intersection);
}

Severity? _severityFromString(String s) {
  switch (s) {
    case 'fatal':
      return Severity.fatal;
    case 'error':
      return Severity.error;
    case 'warning':
      return Severity.warning;
    case 'note':
      return Severity.note;
    case 'none':
      return Severity.none;
    default:
      return null;
  }
}
