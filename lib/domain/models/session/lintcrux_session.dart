// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';
import 'package:meta/meta.dart';

/// In-memory representation of a `.lintcrux-session` file.
///
/// The session is the per-tab UI snapshot — distinct from the
/// `.lintcrux` project file (which carries source-file list, defines,
/// engine config). Exported by `File → Save Session As…` and
/// re-loadable via `File → Open Session…` or
/// `lintcrux project.lintcrux --session debug.lintcrux-session`.
///
/// Schema version 1; unknown keys are silently dropped on load so
/// future fields don't break older clients, and unknown major
/// versions are rejected with a clear error message.
@immutable
class LintcruxSession {
  /// Creates a [LintcruxSession]. `version` defaults to the current
  /// schema version (1).
  const LintcruxSession({
    required this.projectPath,
    this.version = 1,
    this.selectedRuleId,
    this.activeSeverities = const <Severity>{},
    this.activeEngineIds = const <String>{},
    this.ruleSubstring = '',
    this.fileGlob = '',
    this.sortColumn = ViolationTableColumn.severity,
    this.sortAscending = true,
    this.savedFilterPresetName,
    this.viewMode = ViewMode.table,
  });

  /// Deserializes from JSON. Throws [LintcruxSessionLoadException] if
  /// the schema version is unsupported or required fields are missing.
  factory LintcruxSession.fromJson(Map<String, Object?> map) {
    final version = map['version'];
    if (version is! int) {
      throw const LintcruxSessionLoadException(
        'Missing "version" field; not a LintCrux session file.',
      );
    }
    if (version > currentVersion) {
      throw LintcruxSessionLoadException(
        'Session file uses schema version $version, but this build '
        'only understands up to $currentVersion. Upgrade LintCrux.',
      );
    }
    final projectPath = map['projectPath'];
    if (projectPath is! String) {
      throw const LintcruxSessionLoadException(
        'Missing "projectPath" field.',
      );
    }
    final severitiesRaw = map['activeSeverities'];
    final severities = <Severity>{};
    if (severitiesRaw is List) {
      for (final e in severitiesRaw) {
        if (e is! String) continue;
        for (final s in Severity.values) {
          if (s.name == e) {
            severities.add(s);
            break;
          }
        }
      }
    }
    final engineIdsRaw = map['activeEngineIds'];
    final engineIds = <String>{};
    if (engineIdsRaw is List) {
      engineIds.addAll(engineIdsRaw.whereType<String>());
    }
    return LintcruxSession(
      version: version,
      projectPath: projectPath,
      selectedRuleId: map['selectedRuleId'] is String
          ? map['selectedRuleId']! as String
          : null,
      activeSeverities: Set<Severity>.unmodifiable(severities),
      activeEngineIds: Set<String>.unmodifiable(engineIds),
      ruleSubstring: map['ruleSubstring'] is String
          ? map['ruleSubstring']! as String
          : '',
      fileGlob: map['fileGlob'] is String ? map['fileGlob']! as String : '',
      sortColumn: _parseSortColumn(map['sortColumn']),
      sortAscending:
          map['sortAscending'] is! bool || (map['sortAscending']! as bool),
      savedFilterPresetName: map['savedFilterPresetName'] is String
          ? map['savedFilterPresetName']! as String
          : null,
      viewMode: _parseViewMode(map['viewMode']),
    );
  }

  /// Current `.lintcrux-session` schema version. Bumping this signals
  /// a breaking change; older clients reject the file.
  static const int currentVersion = 1;

  /// Schema version that produced this session.
  final int version;

  /// Absolute path of the `.lintcrux` project file this session was
  /// exported for. On load, the project is opened (if not already)
  /// and the rest of the session state applied on top.
  final String projectPath;

  /// Engine-namespaced rule id of the currently selected violation, or
  /// `null` if no row was selected at export time.
  final String? selectedRuleId;

  /// Active severity filter chips.
  final Set<Severity> activeSeverities;

  /// Active engine filter chips.
  final Set<String> activeEngineIds;

  /// Rule substring filter value at export time.
  final String ruleSubstring;

  /// File glob filter value at export time.
  final String fileGlob;

  /// Sort column at export time.
  final ViolationTableColumn sortColumn;

  /// Whether the sort was ascending at export time.
  final bool sortAscending;

  /// Name of the saved filter preset that was active at export time,
  /// or `null` if the user had a free-form filter combination.
  final String? savedFilterPresetName;

  /// Layout mode at export time — table vs. detail-focused.
  final ViewMode viewMode;

  /// Serializes to JSON for the `.lintcrux-session` file.
  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'projectPath': projectPath,
    if (selectedRuleId != null) 'selectedRuleId': selectedRuleId,
    'activeSeverities': [for (final s in activeSeverities) s.name],
    'activeEngineIds': activeEngineIds.toList(),
    'ruleSubstring': ruleSubstring,
    'fileGlob': fileGlob,
    'sortColumn': sortColumn.name,
    'sortAscending': sortAscending,
    if (savedFilterPresetName != null)
      'savedFilterPresetName': savedFilterPresetName,
    'viewMode': viewMode.name,
  };

  static ViolationTableColumn _parseSortColumn(Object? raw) {
    if (raw is String) {
      for (final c in ViolationTableColumn.values) {
        if (c.name == raw) return c;
      }
    }
    return ViolationTableColumn.severity;
  }

  static ViewMode _parseViewMode(Object? raw) {
    if (raw is String) {
      for (final m in ViewMode.values) {
        if (m.name == raw) return m;
      }
    }
    return ViewMode.table;
  }
}

/// View mode the session was saved in. `table` shows the violation
/// table; `detailFocused` shows the inspector + source preview with a
/// collapsed table.
enum ViewMode {
  /// Standard violation-table view.
  table,

  /// Detail-focused view — inspector + source preview occupy more
  /// of the screen.
  detailFocused,
}

/// Raised by [LintcruxSession.fromJson] on a malformed / unsupported
/// session file.
class LintcruxSessionLoadException implements Exception {
  /// Creates a [LintcruxSessionLoadException].
  const LintcruxSessionLoadException(this.message);

  /// English explanation of the failure; the snackbar wraps this.
  final String message;

  @override
  String toString() => 'LintcruxSessionLoadException: $message';
}
