// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/enums/violation_view_mode.dart';
import 'package:lintcrux/domain/interfaces/violation_store.dart';
import 'package:lintcrux/domain/models/baseline_violation.dart';
import 'package:lintcrux/domain/models/filter_preset.dart';
import 'package:lintcrux/domain/models/lint_baseline.dart';
import 'package:lintcrux/domain/models/named_filter_preset.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';
import 'package:lintcrux/features/violations/providers/violation_view_mode_provider.dart';
import 'package:lintcrux/services/baseline/current_baseline_snapshot_provider.dart';
import 'package:lintcrux/services/filter_presets/active_filter_preset_provider.dart';
import 'package:lintcrux/services/filter_presets/filter_preset_overlay.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';

/// Placeholder retention key for "no project loaded" — mirrors
/// `crux_projects`' `emptyWorkspaceProjectId` without depending on that
/// package's root-scoped, asynchronously-converging project registry
/// (see the class doc below for why that dependency was a bug).
const String _noProjectId = '<none>';

/// Riverpod notifier for the violation table's filter / sort / select
/// state.
///
/// Per-project: the notifier keeps one [ViolationTableState] per project
/// root path so a tab whose project changes doesn't inherit the previous
/// project's filter/sort/column-visibility state. `build` watches this
/// TAB's own [currentProjectProvider] (this provider is rebound per tab
/// by `lintcruxTabOverridesFactory`, so each tab already has an isolated
/// instance) and keys retention off the project's `rootPath`.
///
/// Previously this watched the root-scoped `activeProjectIdProvider`
/// (from `crux_projects`), which only updates after `ProjectWorkspaceSync`
/// asynchronously converges the tab-open event into the project registry
/// — a multi-hop process with real await gaps. Any filter/sort state
/// applied synchronously right after opening a project (e.g. session
/// replay in `OpenProjectInWorkspace.openSession`) was written under the
/// STALE id, then silently discarded when the registry catch-up fired a
/// rebuild keyed to the new id. Because `activeProjectIdProvider` is also
/// root-scoped — shared by every tab's `ViolationTableNotifier` alike —
/// the same rebuild could reshuffle every open tab's retention slot at
/// once. Keying off this tab's own `currentProjectProvider` closes both
/// gaps: the id updates synchronously with the project load, and it is
/// intrinsically tab-scoped.
class ViolationTableNotifier extends Notifier<ViolationTableState> {
  final Map<String, ViolationTableState> _perProject =
      <String, ViolationTableState>{};
  String _activeId = _noProjectId;

  @override
  ViolationTableState build() {
    _activeId = ref.watch(currentProjectProvider)?.rootPath ?? _noProjectId;
    return _perProject[_activeId] ?? ViolationTableState.initial;
  }

  /// Commits [next] both as the live [state] and into the active project's
  /// retained slot, so switching away and back restores it.
  void _set(ViolationTableState next) {
    _perProject[_activeId] = next;
    state = next;
  }

  /// Toggle the severity in the active filter set.
  void toggleSeverity(Severity s) {
    final next = Set<Severity>.from(state.severities);
    if (next.contains(s)) {
      next.remove(s);
    } else {
      next.add(s);
    }
    _set(state.copyWith(severities: Set<Severity>.unmodifiable(next)));
  }

  /// Toggle the engine in the active filter set.
  void toggleEngine(String engineId) {
    final next = Set<String>.from(state.engineIds);
    if (next.contains(engineId)) {
      next.remove(engineId);
    } else {
      next.add(engineId);
    }
    _set(state.copyWith(engineIds: Set<String>.unmodifiable(next)));
  }

  /// Set the rule substring filter (case-insensitive matches over
  /// ruleId + message). Empty string clears the filter.
  void setRuleSubstring(String s) {
    _set(state.copyWith(ruleSubstring: s));
  }

  /// Set the file glob filter. Empty string clears the filter.
  void setFileGlob(String s) {
    _set(state.copyWith(fileGlob: s));
  }

  /// Click a column header: ascending if it's a new column, otherwise
  /// flip ascending/descending.
  void cycleSort(ViolationTableColumn col) {
    if (state.sortColumn != col) {
      _set(state.copyWith(sortColumn: col, sortAscending: true));
    } else {
      _set(state.copyWith(sortAscending: !state.sortAscending));
    }
  }

  /// Set the sort column explicitly (ascending). Used by the Settings →
  /// General default-sort-column dropdown so the user's choice takes
  /// effect immediately.
  void setSortColumn(ViolationTableColumn col) {
    if (state.sortColumn == col) return;
    _set(state.copyWith(sortColumn: col, sortAscending: true));
  }

  /// Set both the sort column and direction explicitly. Used to restore
  /// a previously-captured sort state verbatim — session replay
  /// (`OpenProjectInWorkspace.openSession`) and workspace-tab hydration
  /// (`ProjectTabContent`) — where [setSortColumn]'s always-ascending
  /// behavior would silently drop a descending sort on restore.
  void setSort(ViolationTableColumn col, {required bool ascending}) {
    if (state.sortColumn == col && state.sortAscending == ascending) return;
    _set(state.copyWith(sortColumn: col, sortAscending: ascending));
  }

  /// Apply every filter dimension from [preset] to the table. The sort
  /// column and selection are intentionally NOT touched — sort is a
  /// table-level UI concern, and selection is a transient overlay.
  void applyFromPreset(NamedFilterPreset preset) {
    _set(
      state.copyWith(
        severities: Set<Severity>.unmodifiable(preset.severities),
        engineIds: Set<String>.unmodifiable(preset.engineIds),
        ruleSubstring: preset.ruleSubstring,
        fileGlob: preset.fileGlob,
      ),
    );
  }

  /// Copy every filter dimension from [next] in one shot.
  /// Used by the CXP receive-side dispatcher
  /// (`cxpServerLifecycleProvider`) to apply the filter computed by
  /// [LintCruxCxpRequestHandler]. Sort and selection are intentionally
  /// not touched — sort is a table-level UI concern, and selection is
  /// managed by [selectedViolationProvider].
  void applyFromState(ViolationTableState next) {
    _set(
      state.copyWith(
        severities: next.severities,
        engineIds: next.engineIds,
        ruleSubstring: next.ruleSubstring,
        fileGlob: next.fileGlob,
      ),
    );
  }

  /// Toggle selection of one row.
  void toggleSelection(String violationId) {
    final next = Set<String>.from(state.selectedRuleIds);
    if (next.contains(violationId)) {
      next.remove(violationId);
    } else {
      next.add(violationId);
    }
    _set(state.copyWith(selectedRuleIds: Set<String>.unmodifiable(next)));
  }

  /// Select all visible rows.
  void selectAll(Iterable<Violation> visible) {
    final next = visible.map(ViolationTableState.idOf).toSet();
    _set(state.copyWith(selectedRuleIds: Set<String>.unmodifiable(next)));
  }

  /// Clear selection.
  void clearSelection() {
    _set(state.copyWith(selectedRuleIds: const <String>{}));
  }

  /// Reset the entire table state to initial. Convenient for tests.
  void reset() {
    _set(ViolationTableState.initial);
  }
}

/// Riverpod provider exposing the violation table state.
final NotifierProvider<ViolationTableNotifier, ViolationTableState>
violationTableStateProvider =
    NotifierProvider<ViolationTableNotifier, ViolationTableState>(
      ViolationTableNotifier.new,
    );

/// Notifier driving [visibleViolationsProvider]: subscribes to the
/// violation store's events stream and re-emits the filtered, sorted
/// list on every mutation (or when the table state changes).
class VisibleViolationsNotifier extends Notifier<List<Violation>> {
  // The subscription is cancelled in `ref.onDispose` and in `build`
  // when the store identity changes; the lint can't see across those
  // boundaries.
  // ignore: cancel_subscriptions
  StreamSubscription<ViolationStoreEvent>? _sub;

  @override
  List<Violation> build() {
    final store = ref.watch(violationStoreProvider);
    final tableState = ref.watch(violationTableStateProvider);
    final viewMode = ref.watch(violationViewModeProvider);
    final baselineSnapshot = ref.watch(currentBaselineSnapshotProvider);
    final activePreset = ref.watch(activeFilterPresetProvider);
    final projectRoot = ref.watch(
      currentProjectProvider.select((p) => p?.rootPath ?? ''),
    );
    // Re-subscribe each time the store identity changes (e.g. when
    // tests override `violationStoreProvider`).
    final old = _sub;
    if (old != null) unawaited(old.cancel());
    _sub = store.events.listen((_) => _recompute());
    ref.onDispose(() {
      final sub = _sub;
      if (sub != null) unawaited(sub.cancel());
    });
    return _derive(
      store,
      tableState,
      viewMode,
      baselineSnapshot,
      activePreset,
      projectRoot,
    );
  }

  void _recompute() {
    final store = ref.read(violationStoreProvider);
    final tableState = ref.read(violationTableStateProvider);
    final viewMode = ref.read(violationViewModeProvider);
    final baselineSnapshot = ref.read(currentBaselineSnapshotProvider);
    final activePreset = ref.read(activeFilterPresetProvider);
    final projectRoot = ref.read(currentProjectProvider)?.rootPath ?? '';
    state = _derive(
      store,
      tableState,
      viewMode,
      baselineSnapshot,
      activePreset,
      projectRoot,
    );
  }

  List<Violation> _derive(
    ViolationStore store,
    ViolationTableState tableState,
    ViolationViewMode viewMode,
    LintBaseline? baseline,
    FilterPreset? activePreset,
    String projectRoot,
  ) {
    // Overlay the active filter preset on top of the user-supplied table state.
    // When no preset is active the overlay is the identity, so the existing
    // table-state-only behavior is preserved exactly.
    final overlay = overlayFilterPreset(
      preset: activePreset,
      baseFilter: tableState.toFilter(),
      baseViewMode: viewMode,
    );
    final filtered = store.filter(overlay.effectiveFilter);
    _sortInPlace(filtered, tableState.sortColumn, tableState.sortAscending);
    return List<Violation>.unmodifiable(
      _applyViewModePostFilter(
        filtered,
        overlay.effectiveViewMode,
        baseline,
        projectRoot,
      ),
    );
  }
}

/// Applies the active [ViolationViewMode] post-filter to [filtered].
///
/// When [viewMode] is [ViolationViewMode.allViolations] or when
/// [baseline] is `null` (no Pro baseline set), returns [filtered]
/// unchanged. Otherwise filters down to:
///
/// - [ViolationViewMode.onlyNew] — violations whose fingerprint is
///   *not* present in the baseline (the `newViolations` slice of
///   [BaselineDelta]).
/// - [ViolationViewMode.onlyResolved] — empty list because resolved
///   entries are baseline-frozen (not live violations) and therefore
///   never appear in the live filter result. The Pro overlay surfaces
///   resolved violations through a dedicated path that reads
///   [LintBaseline.frozenViolations] directly; the violation table
///   itself only renders live `Violation` instances, so
///   `onlyResolved` shows an empty list in the table while the
///   resolved-section views handle the actual rendering.
///
/// Exposed top-level so widget code that needs the same logic
/// (e.g. the Pro status chip's resolved-count cache) can reuse it.
List<Violation> _applyViewModePostFilter(
  List<Violation> filtered,
  ViolationViewMode viewMode,
  LintBaseline? baseline,
  String projectRoot,
) {
  if (viewMode == ViolationViewMode.allViolations || baseline == null) {
    return filtered;
  }
  final baselineFingerprints = baseline.fingerprintSet;
  switch (viewMode) {
    case ViolationViewMode.allViolations:
      return filtered;
    case ViolationViewMode.onlyNew:
      return <Violation>[
        for (final v in filtered)
          if (!baselineFingerprints.contains(
            baselineFingerprintFor(v, projectRoot: projectRoot),
          ))
            v,
      ];
    case ViolationViewMode.onlyResolved:
      // Live `Violation` instances cannot be "resolved" baseline
      // entries by definition (the engine is reporting them right
      // now). The resolved view is rendered by Pro screens that read
      // `LintBaseline.frozenViolations` directly; the table itself
      // shows an empty list under this mode.
      return const <Violation>[];
  }
}

/// Live filtered + sorted violation list, updated on every store
/// mutation and every filter/sort change.
final NotifierProvider<VisibleViolationsNotifier, List<Violation>>
visibleViolationsProvider =
    NotifierProvider<VisibleViolationsNotifier, List<Violation>>(
      VisibleViolationsNotifier.new,
    );

void _sortInPlace(
  List<Violation> list,
  ViolationTableColumn col,
  bool asc,
) {
  int cmp(Violation a, Violation b) {
    switch (col) {
      case ViolationTableColumn.severity:
        return severityCompare(a.severity, b.severity);
      case ViolationTableColumn.engine:
        return a.engineId.compareTo(b.engineId);
      case ViolationTableColumn.rule:
        return a.ruleId.compareTo(b.ruleId);
      case ViolationTableColumn.file:
        final byFile = a.location.file.compareTo(b.location.file);
        if (byFile != 0) return byFile;
        final byLine = a.location.line.compareTo(b.location.line);
        if (byLine != 0) return byLine;
        return a.location.column.compareTo(b.location.column);
      case ViolationTableColumn.line:
        final byLine = a.location.line.compareTo(b.location.line);
        if (byLine != 0) return byLine;
        return a.location.column.compareTo(b.location.column);
      case ViolationTableColumn.message:
        return a.message.compareTo(b.message);
    }
  }

  list.sort((a, b) => asc ? cmp(a, b) : -cmp(a, b));
}
