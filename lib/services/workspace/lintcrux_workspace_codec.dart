// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_io/crux_io.dart';
import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/lintcrux_tab_payload.dart';
import 'package:lintcrux/domain/models/session/lintcrux_session.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';
import 'package:path/path.dart' as p;

/// LintCrux-specific implementation of `crux_workspace`'s
/// [crux.WorkspaceCodec] interface.
///
/// Round-trips a [LintcruxTabPayload] through the workspace document.
/// The JSON shape matches schema v1 of [LintcruxSession] minus the
/// framework-controlled keys (`id`, `displayName`, `paneId`, and
/// `version` — the framework owns the workspace-level schema version,
/// and the per-tab payload's schema is versioned independently via
/// [schemaVersion]). On corrupt or partially-valid input, the codec
/// silently falls back to constructor defaults so the workspace
/// service's "load returns Workspace.empty()" failure mode still
/// applies — but a partially-corrupt tab is hydrated with whatever
/// fields are valid rather than dropped entirely.
class LintcruxWorkspaceCodec extends crux.WorkspaceCodec<LintcruxTabPayload> {
  /// Creates a stateless codec instance. One per app is sufficient.
  const LintcruxWorkspaceCodec();

  /// Per-tab payload schema version. Bumped within the product when
  /// payload-internal fields change in a non-backward-compatible way.
  ///
  /// The framework's `kWorkspaceSchemaVersion` handles workspace-level
  /// schema migration separately.
  @override
  int get schemaVersion => 1;

  @override
  Map<String, Object?> payloadToJson(LintcruxTabPayload payload) {
    return <String, Object?>{
      'projectPath': payload.projectPath,
      if (payload.selectedRuleId != null)
        'selectedRuleId': payload.selectedRuleId,
      'activeSeverities': [for (final s in payload.activeSeverities) s.name],
      'activeEngineIds': payload.activeEngineIds.toList(growable: false),
      'ruleSubstring': payload.ruleSubstring,
      'fileGlob': payload.fileGlob,
      'sortColumn': payload.sortColumn.name,
      'sortAscending': payload.sortAscending,
      if (payload.savedFilterPresetName != null)
        'savedFilterPresetName': payload.savedFilterPresetName,
      'viewMode': payload.viewMode.name,
      if (payload.sessionExportPath != null)
        'sessionExportPath': payload.sessionExportPath,
    };
  }

  @override
  LintcruxTabPayload payloadFromJson(Map<String, Object?> json) {
    final projectPath = json['projectPath'];
    if (projectPath is! String || projectPath.isEmpty) {
      throw const crux.WorkspaceInvariantException(
        'LintcruxTabPayload requires a non-empty projectPath',
      );
    }

    final severitiesRaw = json['activeSeverities'];
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

    final engineIdsRaw = json['activeEngineIds'];
    final engineIds = <String>{};
    if (engineIdsRaw is List) {
      engineIds.addAll(engineIdsRaw.whereType<String>());
    }

    return LintcruxTabPayload(
      projectPath: projectPath,
      selectedRuleId: json['selectedRuleId'] is String
          ? json['selectedRuleId']! as String
          : null,
      activeSeverities: Set<Severity>.unmodifiable(severities),
      activeEngineIds: Set<String>.unmodifiable(engineIds),
      ruleSubstring: json['ruleSubstring'] is String
          ? json['ruleSubstring']! as String
          : '',
      fileGlob: json['fileGlob'] is String ? json['fileGlob']! as String : '',
      sortColumn: _parseSortColumn(json['sortColumn']),
      // `sortAscending` defaults to `true` when missing or wrong-typed.
      // We can't use `(json['sortAscending'] as bool?) ?? true` because
      // a wrong-typed value (e.g. a String left behind by a buggy
      // exporter) would throw on the cast — silent fallback is the
      // documented contract. `!= false` collapses the conditional
      // without the `?? true` cast risk: any non-bool stays truthy.
      sortAscending:
          json['sortAscending'] is! bool || (json['sortAscending']! as bool),
      savedFilterPresetName: json['savedFilterPresetName'] is String
          ? json['savedFilterPresetName']! as String
          : null,
      viewMode: _parseViewMode(json['viewMode']),
      sessionExportPath: json['sessionExportPath'] is String
          ? json['sessionExportPath']! as String
          : null,
    );
  }

  /// Canonical identity of a LintCrux tab: the `.lintcrux` project file it
  /// hosts, reduced to a [canonicalPathKey].
  ///
  /// This is what makes a second open of an already-open project *focus*
  /// that project's tab instead of stacking another copy of it — see
  /// `crux.WorkspaceNotifier.openTab`'s `dedupe` parameter. Before the
  /// codec opted in, every CLI launch carrying a positional `.lintcrux`
  /// path appended one more tab for the same project, without bound (seven
  /// identical tabs were observed in the field).
  ///
  /// The key — not the raw [LintcruxTabPayload.projectPath] — is the
  /// identity because none of the spellings a project path arrives in are
  /// canonical: a shell passes `./riscv-soc.lintcrux`, the restored
  /// workspace document holds the absolute path it was saved with, a
  /// `Makefile` passes `../soc/./riscv-soc.lintcrux`, macOS resolves
  /// `/tmp` to `/private/tmp`, and APFS/NTFS ignore case. Each of those
  /// mismatches presents as a duplicate tab that returns every launch.
  ///
  /// An empty path is the empty-canvas tab, which has no identity: it
  /// returns `null` so two blank tabs stay openable.
  ///
  /// The key is namespaced (`project:<key>`). LintCrux tabs are all of one
  /// kind today, so the prefix buys nothing yet — it is here so that a
  /// second payload kind (a raw-source tab, a SARIF-import tab) cannot
  /// collide with a project tab merely by naming the same file. Two payload
  /// kinds are the same thing to the user only if they are the same kind,
  /// and that should hold by construction rather than by path spelling.
  @override
  String? identityOf(LintcruxTabPayload payload) {
    final path = payload.projectPath;
    if (path.isEmpty) return null;
    final key = canonicalPathKey(path);
    return key.isEmpty ? null : 'project:$key';
  }

  @override
  String displayNameFor(LintcruxTabPayload payload) {
    final base = p.basenameWithoutExtension(payload.projectPath);
    if (base.isEmpty) return p.basename(payload.projectPath);
    return base;
  }

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
