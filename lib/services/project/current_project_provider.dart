// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async' show unawaited;

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/core/policy/lintcrux_policy_keys.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/named_filter_preset.dart';
import 'package:lintcrux/services/project/project_file_service.dart';
import 'package:lintcrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:path/path.dart' as p;

/// Currently loaded project, or `null` when none is open.
///
/// Declared at the root scope and re-hosted in each tab's `ProviderContainer`
/// so each tab carries its own project (mirroring WaveCrux's per-tab
/// `waveformSourceProvider`).
final NotifierProvider<CurrentProjectNotifier, LintProject?>
currentProjectProvider = NotifierProvider<CurrentProjectNotifier, LintProject?>(
  CurrentProjectNotifier.new,
);

/// Notifier exposing `set` / `clear` over the currently-loaded project.
class CurrentProjectNotifier extends Notifier<LintProject?> {
  @override
  LintProject? build() => null;

  String? _projectFilePath;

  /// Serializes [updateProjectFile] so two quick edits cannot interleave
  /// their read-modify-write of the same file.
  Future<void> _writes = Future<void>.value();

  /// The `.lintcrux` file the loaded project was read from, or `null` when
  /// the caller of [load] did not name one.
  String? get projectFilePath => _projectFilePath;

  /// Load [project] as the currently active project, replacing any
  /// prior project. Kept as an action verb (not a setter) so call
  /// sites read as `notifier.load(project)` matching the
  /// `runAll(project)` / `cancel()` mutators on neighboring run
  /// notifiers.
  ///
  /// [projectFilePath] is the `.lintcrux` file [project] was read from.
  /// Every open path knows it and passes it; it is what [updateProjectFile]
  /// writes, so an edit made in the app reaches the file the user opened.
  void load(LintProject project, {String? projectFilePath}) {
    state = project;
    _projectFilePath = projectFilePath;
    // Record this design in the shared workspace so a peer can resolve + open
    // it later. Best-effort and gated on the CXP server running (inside the
    // helper), so it early-returns to a no-op with CXP off or in unit tests.
    // Keyed by the design's `.lintcrux` file; without a named file it is
    // reconstructed from the project's root + name (the inverse of how the open
    // path derives them from the picked file path).
    final projectPath =
        projectFilePath ?? p.join(project.rootPath, '${project.name}.lintcrux');
    unawaited(publishLintcruxProjectArtifact(ref, projectPath, project));
  }

  /// Convenience: clear the loaded project.
  void clear() {
    state = null;
    _projectFilePath = null;
  }

  /// Applies [update] to the project **as authored on disk** and writes it
  /// back to [projectFilePath].
  ///
  /// The file is re-read rather than the in-memory project serialized: the
  /// loaded project has every path resolved to absolute, and writing that
  /// would rewrite a portable, committed `.lintcrux` full of this machine's
  /// paths. Writes are serialized. Completes without writing when no
  /// project file is known, and with a [ProjectFileException] when the file
  /// cannot be read or written — the caller reports it.
  Future<void> updateProjectFile(
    LintProject Function(LintProject authored) update,
  ) {
    final path = _projectFilePath;
    if (path == null) return Future<void>.value();
    final write = _writes.then((_) async {
      const service = ProjectFileService();
      final authored = await service.read(path);
      await service.write(path, update(authored));
    });
    _writes = write.catchError((Object _) {});
    return write;
  }

  /// Replaces the loaded project's `filterPresets` in memory. No-op when
  /// no project is loaded. Callers that want the change saved follow it
  /// with [updateProjectFile].
  void setFilterPresets(List<NamedFilterPreset> presets) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(filterPresets: presets);
  }

  /// [setSeverityOverride], then the same change written to the project
  /// file so it survives closing the tab and reaches the team and CI.
  ///
  /// Only [ruleId]'s entry in the file's `severityOverrides` changes; the
  /// rest of the project is written back as it was read.
  Future<void> saveSeverityOverride(String ruleId, Severity? severity) {
    setSeverityOverride(ruleId, severity);
    return updateProjectFile((authored) {
      final next = Map<String, Severity>.from(authored.severityOverrides);
      if (severity == null) {
        next.remove(ruleId);
      } else {
        next[ruleId] = severity;
      }
      return authored.copyWith(severityOverrides: next);
    });
  }

  /// Sets the severity override for [ruleId] (engine-namespaced) to
  /// [severity], or removes the override when [severity] is `null`.
  /// No-op when no project is loaded.
  ///
  /// Recorded as [LintCruxAuditKinds.severityOverridden]. Downgrading a rule
  /// is the single most consequential thing a user can do to a lint result —
  /// it is how a real violation stops being reported — so an organization that
  /// turned auditing on wants both the old and the new severity, not just the
  /// new one. Inert unless an administrator configured `suite.audit.path`; the
  /// sink is what is gated, never the emission.
  void setSeverityOverride(String ruleId, Severity? severity) {
    final current = state;
    if (current == null) return;
    final previous = current.severityOverrides[ruleId];
    final next = Map<String, Severity>.from(current.severityOverrides);
    if (severity == null) {
      next.remove(ruleId);
    } else {
      next[ruleId] = severity;
    }
    // No state change, nothing to record — re-selecting the severity a rule
    // already has is not an event.
    if (previous == severity) return;
    state = current.copyWith(
      severityOverrides: Map<String, Severity>.unmodifiable(next),
    );
    ref
        .read(cruxAuditRecorderProvider)
        .record(
          LintCruxAuditKinds.severityOverridden,
          payload: <String, Object?>{
            'ruleId': ruleId,
            'from': previous?.name,
            // Null means the override was removed and the rule is back to the
            // engine's own severity, which is a different event from setting
            // one and must not read as the same.
            'to': severity?.name,
            'project': current.name,
          },
        );
  }
}
