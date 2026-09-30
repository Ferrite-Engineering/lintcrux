// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/session/lintcrux_session.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';
import 'package:meta/meta.dart';

/// Per-tab payload type supplied to `crux_workspace`'s
/// `WorkspaceTab<P>`.
///
/// Carries the persistence-relevant slice of one tab's state: the
/// `.lintcrux` project file path, the selection cursor, the violation
/// table's filter / sort state, the active saved-filter-preset name,
/// the view mode, and (optionally) the path of the last
/// `.lintcrux-session` this tab was exported to. Heavyweight per-tab
/// state (the loaded `LintProject`, the `ViolationStore`, the
/// `LintRunNotifier`, the `AutoReloadController`) lives in the tab's
/// per-tab Riverpod `ProviderContainer` — the payload is the
/// framework-visible summary needed to re-bind the project on
/// restore.
///
/// Round-trips through [LintcruxWorkspaceCodec]; the JSON shape mirrors
/// the schema-v1 [LintcruxSession] fields except for `version` (the
/// framework controls the workspace-level schema version) and
/// `projectPath` (renamed to that here to match the LintCrux domain
/// vocabulary — it's the same field).
@immutable
class LintcruxTabPayload {
  /// Creates a [LintcruxTabPayload].
  const LintcruxTabPayload({
    required this.projectPath,
    this.selectedRuleId,
    this.activeSeverities = const <Severity>{},
    this.activeEngineIds = const <String>{},
    this.ruleSubstring = '',
    this.fileGlob = '',
    this.sortColumn = ViolationTableColumn.severity,
    this.sortAscending = true,
    this.savedFilterPresetName,
    this.viewMode = ViewMode.table,
    this.sessionExportPath,
  });

  /// Builds a payload from a fully-loaded session document (used by the
  /// session import flow). Mirrors every field one-for-one.
  factory LintcruxTabPayload.fromSession(LintcruxSession session) {
    return LintcruxTabPayload(
      projectPath: session.projectPath,
      selectedRuleId: session.selectedRuleId,
      activeSeverities: Set<Severity>.unmodifiable(session.activeSeverities),
      activeEngineIds: Set<String>.unmodifiable(session.activeEngineIds),
      ruleSubstring: session.ruleSubstring,
      fileGlob: session.fileGlob,
      sortColumn: session.sortColumn,
      sortAscending: session.sortAscending,
      savedFilterPresetName: session.savedFilterPresetName,
      viewMode: session.viewMode,
    );
  }

  /// Absolute path of the `.lintcrux` project file this tab hosts.
  ///
  /// Required — a tab with no project file has nothing to bind.
  final String projectPath;

  /// Engine-namespaced rule id of the currently selected violation, or
  /// `null` when no row is selected.
  final String? selectedRuleId;

  /// Active severity filter chips. Empty set means "all severities".
  final Set<Severity> activeSeverities;

  /// Active engine filter chips. Empty set means "all engines".
  final Set<String> activeEngineIds;

  /// Rule substring filter value (case-insensitive substring over
  /// `ruleId` + `message`). Empty string clears the filter.
  final String ruleSubstring;

  /// File glob filter value. Empty string clears the filter.
  final String fileGlob;

  /// Sort column for the violation table.
  final ViolationTableColumn sortColumn;

  /// Whether the sort is ascending.
  final bool sortAscending;

  /// Name of the saved filter preset that is currently active, or
  /// `null` when the user has a free-form filter combination.
  final String? savedFilterPresetName;

  /// Layout mode — table vs. detail-focused.
  final ViewMode viewMode;

  /// Path of the last `.lintcrux-session` file this tab was exported
  /// to, or `null` when the tab has never been exported. Used to
  /// hint the destination on subsequent exports.
  final String? sessionExportPath;

  /// Returns a copy with the given fields replaced.
  LintcruxTabPayload copyWith({
    String? projectPath,
    String? selectedRuleId,
    Set<Severity>? activeSeverities,
    Set<String>? activeEngineIds,
    String? ruleSubstring,
    String? fileGlob,
    ViolationTableColumn? sortColumn,
    bool? sortAscending,
    String? savedFilterPresetName,
    ViewMode? viewMode,
    String? sessionExportPath,
  }) {
    return LintcruxTabPayload(
      projectPath: projectPath ?? this.projectPath,
      selectedRuleId: selectedRuleId ?? this.selectedRuleId,
      activeSeverities: activeSeverities ?? this.activeSeverities,
      activeEngineIds: activeEngineIds ?? this.activeEngineIds,
      ruleSubstring: ruleSubstring ?? this.ruleSubstring,
      fileGlob: fileGlob ?? this.fileGlob,
      sortColumn: sortColumn ?? this.sortColumn,
      sortAscending: sortAscending ?? this.sortAscending,
      savedFilterPresetName:
          savedFilterPresetName ?? this.savedFilterPresetName,
      viewMode: viewMode ?? this.viewMode,
      sessionExportPath: sessionExportPath ?? this.sessionExportPath,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LintcruxTabPayload) return false;
    if (projectPath != other.projectPath) return false;
    if (selectedRuleId != other.selectedRuleId) return false;
    if (ruleSubstring != other.ruleSubstring) return false;
    if (fileGlob != other.fileGlob) return false;
    if (sortColumn != other.sortColumn) return false;
    if (sortAscending != other.sortAscending) return false;
    if (savedFilterPresetName != other.savedFilterPresetName) return false;
    if (viewMode != other.viewMode) return false;
    if (sessionExportPath != other.sessionExportPath) return false;
    if (activeSeverities.length != other.activeSeverities.length) return false;
    if (!activeSeverities.containsAll(other.activeSeverities)) return false;
    if (activeEngineIds.length != other.activeEngineIds.length) return false;
    if (!activeEngineIds.containsAll(other.activeEngineIds)) return false;
    return true;
  }

  @override
  int get hashCode => Object.hash(
    projectPath,
    selectedRuleId,
    Object.hashAllUnordered(activeSeverities),
    Object.hashAllUnordered(activeEngineIds),
    ruleSubstring,
    fileGlob,
    sortColumn,
    sortAscending,
    savedFilterPresetName,
    viewMode,
    sessionExportPath,
  );

  @override
  String toString() =>
      'LintcruxTabPayload(projectPath: $projectPath, '
      'selectedRuleId: $selectedRuleId, '
      'activeSeverities: $activeSeverities, '
      'activeEngineIds: $activeEngineIds, '
      'ruleSubstring: "$ruleSubstring", fileGlob: "$fileGlob", '
      'sortColumn: $sortColumn, sortAscending: $sortAscending, '
      'savedFilterPresetName: $savedFilterPresetName, '
      'viewMode: $viewMode, sessionExportPath: $sessionExportPath)';
}
