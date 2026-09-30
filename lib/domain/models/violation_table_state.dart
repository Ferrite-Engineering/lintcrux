// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/violation_store.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:meta/meta.dart';

/// Sortable columns in the violation table.
enum ViolationTableColumn {
  /// Sort by severity (fatal first, none last).
  severity,

  /// Sort alphabetically by engineId.
  engine,

  /// Sort alphabetically by namespaced ruleId.
  rule,

  /// Sort by file path, then line, then column.
  file,

  /// Sort by line (then column) within each file.
  line,

  /// Sort by message text.
  message,
}

/// Filter + sort + selection state of the violation table.
///
/// All fields are immutable; mutators return new instances.
/// Filtering composes via AND across dimensions; within a dimension,
/// multi-value fields ([severities], [engineIds]) compose via OR.
@immutable
class ViolationTableState {
  /// Creates a [ViolationTableState].
  const ViolationTableState({
    this.severities = const <Severity>{},
    this.engineIds = const <String>{},
    this.ruleSubstring = '',
    this.fileGlob = '',
    this.sortColumn = ViolationTableColumn.severity,
    this.sortAscending = true,
    this.selectedRuleIds = const <String>{},
  });

  /// Empty initial state — no filters, sort by severity ascending.
  static const ViolationTableState initial = ViolationTableState();

  /// Active severity filter; empty means "all severities".
  final Set<Severity> severities;

  /// Active engine filter; empty means "all engines".
  final Set<String> engineIds;

  /// Substring matched (case-insensitive) against ruleId and message.
  final String ruleSubstring;

  /// Glob matched against violation file path.
  final String fileGlob;

  /// Active sort column.
  final ViolationTableColumn sortColumn;

  /// Whether the sort is ascending (true) or descending (false).
  final bool sortAscending;

  /// Selected row identifiers. The identifier scheme is the violation's
  /// "ruleId@file:line:col" tuple — equivalent enough to dedupe by row
  /// across re-runs that emit the same logical violation.
  final Set<String> selectedRuleIds;

  /// Equivalent [ViolationFilter] applied to the store. Selection is
  /// not part of the filter — selection is a UI overlay on top of the
  /// filtered set.
  ViolationFilter toFilter() {
    return ViolationFilter(
      severities: severities.isEmpty ? null : severities,
      engineIds: engineIds.isEmpty ? null : engineIds,
      ruleSubstring: ruleSubstring.isEmpty ? null : ruleSubstring,
      fileGlob: fileGlob.isEmpty ? null : fileGlob,
    );
  }

  /// Returns a copy with overridden fields.
  ViolationTableState copyWith({
    Set<Severity>? severities,
    Set<String>? engineIds,
    String? ruleSubstring,
    String? fileGlob,
    ViolationTableColumn? sortColumn,
    bool? sortAscending,
    Set<String>? selectedRuleIds,
  }) {
    return ViolationTableState(
      severities: severities ?? this.severities,
      engineIds: engineIds ?? this.engineIds,
      ruleSubstring: ruleSubstring ?? this.ruleSubstring,
      fileGlob: fileGlob ?? this.fileGlob,
      sortColumn: sortColumn ?? this.sortColumn,
      sortAscending: sortAscending ?? this.sortAscending,
      selectedRuleIds: selectedRuleIds ?? this.selectedRuleIds,
    );
  }

  /// Stable identifier for a violation row.
  static String idOf(Violation v) =>
      '${v.ruleId}@${v.location.file}:${v.location.line}:${v.location.column}';
}
