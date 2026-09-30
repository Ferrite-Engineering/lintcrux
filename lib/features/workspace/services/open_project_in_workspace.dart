// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/lintcrux_tab_payload.dart';
import 'package:lintcrux/domain/models/session/lintcrux_session.dart';
import 'package:lintcrux/features/project/services/open_project_service.dart';
import 'package:lintcrux/features/run/providers/lint_run_notifier.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/workspace/providers/recent_projects_provider.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/features/workspace/services/crux_project_resolution.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/project/project_file_codec.dart';
import 'package:lintcrux/services/project/project_file_service.dart';
import 'package:lintcrux/services/project/project_path_resolver.dart';
import 'package:lintcrux/services/session/session_service.dart';
import 'package:lintcrux/services/workspace/lintcrux_workspace_codec.dart';
import 'package:path/path.dart' as p;

/// Coordinates opening a `.lintcrux` project file as a new workspace
/// tab.
///
/// Lives in the root [ProviderContainer] because workspace mutations
/// (adding tabs, switching active pane) are root-scoped. The act of
/// loading the project file and storing it in the new tab's
/// per-tab providers is delegated to the package-managed per-tab
/// container, which this controller resolves via the [tabsForId]
/// callback. The callback is supplied by the routed subtree's
/// `WorkspaceRoot` so the controller doesn't have to depend on the
/// widget tree itself.
class OpenProjectInWorkspace {
  /// Creates an [OpenProjectInWorkspace].
  const OpenProjectInWorkspace({
    required this.ref,
    required this.tabsForId,
  });

  /// Riverpod reference used to read the workspace notifier and the
  /// open-project controller.
  final Ref ref;

  /// Callback returning the per-tab `ProviderContainer` for the given
  /// [crux.TabId]. Supplied by the consumer (typically by reading
  /// `WorkspaceRoot.of(context).tabs.containerFor(id)`).
  final ProviderContainer Function(crux.TabId tabId) tabsForId;

  /// Reads [path] as a `.lintcrux` project, opens it in a new
  /// workspace tab, and kicks off a run. The new tab becomes active.
  /// Returns the result so the UI can surface an error snackbar on
  /// failure.
  Future<OpenProjectResult> openProject(String rawPath) async {
    // A `<design>.crux-project` manifest is swapped for the `lint` project it
    // names before anything else runs, so path anchoring, tab creation and
    // the kicked-off run all behave exactly as they do for a directly-opened
    // `.lintcrux`. Placed in the service rather than at the picker so the
    // CLI and recents paths get it too.
    final resolution = const CruxProjectResolver().resolve(rawPath);
    final String path;
    String? legacyRenameTo;
    switch (resolution) {
      case NotAManifest(path: final passthrough):
        path = passthrough;
      case ManifestLintProject(
        :final lintProjectPath,
        legacyRenameTo: final to,
      ):
        path = lintProjectPath;
        legacyRenameTo = to;
      case ManifestAmbiguous(:final error):
        return OpenProjectManifestAmbiguous(error);
      case ManifestUnusable(:final message):
        return OpenProjectFailure(message);
    }

    const service = ProjectFileService();
    final LintProject project;
    try {
      final loaded = await service.read(path);
      // Anchor the project's relative paths (root, sources, includes) at
      // the directory of the picked `.lintcrux` file so engines resolve
      // them regardless of the app's working directory. See
      // `resolveProjectPaths`.
      project = resolveProjectPaths(loaded, p.dirname(path));
    } on ProjectFileException catch (e) {
      return OpenProjectFailure(e.message);
    }
    final notifier = ref.read(workspaceProvider.notifier);
    const codec = LintcruxWorkspaceCodec();
    final payload = LintcruxTabPayload(projectPath: path);
    // Ask *before* opening, because `openTab(dedupe: true)` deliberately
    // returns the existing tab's id without telling the caller it did so —
    // and what happens next differs. A project the user already has open
    // must be *focused*, not reloaded: re-running its engines would discard
    // the run they are looking at and reset the tab's violation table. This
    // is the difference between "relaunching with a project argument brings
    // it forward" and the beta-bug behavior, where every relaunch stacked
    // one more tab of the same project (seven observed).
    final existing = notifier.tabWithSameIdentityAs(payload);
    final tabId = await notifier.openTab(
      displayName: codec.displayNameFor(payload),
      payload: payload,
    );
    // Every successful open — picker, command line, recents, session,
    // cross-probe — feeds the welcome screen's Recent projects list.
    ref
        .read(recentProjectsListProvider.notifier)
        .markOpened(p.normalize(p.absolute(path)));
    if (existing != null) {
      return OpenProjectSuccess(
        project,
        tabId: tabId,
        deduped: true,
        legacyManifestRenameTo: legacyRenameTo,
      );
    }
    final tabContainer = tabsForId(tabId);
    tabContainer
        .read(currentProjectProvider.notifier)
        .load(project, projectFilePath: path);
    // Kick off the run but don't await it: the UI streams violations
    // into the table progressively, and the bootstrap caller doesn't
    // need to block on completion.
    unawaited(
      tabContainer.read(lintRunProvider.notifier).runAll(project),
    );
    return OpenProjectSuccess(
      project,
      tabId: tabId,
      legacyManifestRenameTo: legacyRenameTo,
    );
  }

  /// Reads [path] as a `.lintcrux-session` export, opens its
  /// referenced project in a new tab, and replays the session's
  /// filter / sort / selection state onto the new tab's providers.
  /// Returns the result so the UI can surface an error snackbar on
  /// failure.
  Future<OpenProjectResult> openSession(String path) async {
    // Reuse the existing session decoder.
    final LintcruxSession session;
    try {
      session = await _readSession(path);
    } on Exception catch (e) {
      return OpenProjectFailure(e.toString());
    }
    final loadResult = await openProject(session.projectPath);
    if (loadResult is! OpenProjectSuccess) return loadResult;

    // Use the tab the open actually landed on. Reading `tabs.last` was only
    // ever right while every open appended a tab; with dedupe in place, an
    // `--session` whose project is already open focuses that (possibly
    // leftmost) tab, and replaying the session's filters onto whatever tab
    // happens to sit last would rewrite an unrelated project's state.
    final tabId = loadResult.tabId;
    if (tabId == null) return loadResult;
    final tabContainer = tabsForId(tabId);

    // Apply the session's filter / sort state onto the per-tab
    // violation-table provider.
    final tableNotifier =
        tabContainer.read(violationTableStateProvider.notifier)
          ..setRuleSubstring(session.ruleSubstring)
          ..setFileGlob(session.fileGlob);
    session.activeSeverities.forEach(tableNotifier.toggleSeverity);
    session.activeEngineIds.forEach(tableNotifier.toggleEngine);
    tableNotifier.setSort(session.sortColumn, ascending: session.sortAscending);

    // Mirror the rest of the session into the tab's payload so the
    // workspace document captures it on the next debounced save.
    await ref
        .read(workspaceProvider.notifier)
        .updateTabPayload(
          tabId,
          (current) => LintcruxTabPayload.fromSession(session).copyWith(
            projectPath: current.projectPath,
            sessionExportPath: path,
          ),
        );
    return loadResult;
  }

  /// Loads a `.lintcrux-workspace` named workspace, replacing the
  /// current in-memory workspace document. Each tab's project is
  /// reloaded into its own per-tab container before the active tab
  /// switches. Returns `null` on success, or a [String] error message
  /// on failure.
  Future<String?> openWorkspace(String path) async {
    try {
      final loaded = await ref.read(workspaceProvider.notifier).loadFrom(path);
      // Hydrate each tab's per-tab providers by re-reading its
      // project file.
      const service = ProjectFileService();
      for (final tab in loaded.tabs) {
        try {
          final read = await service.read(tab.payload.projectPath);
          final project = resolveProjectPaths(
            read,
            p.dirname(tab.payload.projectPath),
          );
          final tabContainer = tabsForId(tab.id);
          tabContainer
              .read(currentProjectProvider.notifier)
              .load(project, projectFilePath: tab.payload.projectPath);
        } on ProjectFileException {
          // Skip the unreadable project rather than abort the whole
          // workspace load.
        }
      }
      return null;
    } on Exception catch (e) {
      return e.toString();
    }
  }

  Future<LintcruxSession> _readSession(String path) async {
    const service = SessionService();
    final session = await service.load(path);
    if (session == null) {
      throw const LintcruxSessionLoadException(
        'Session file does not exist.',
      );
    }
    return session;
  }
}

/// Provider exposing the workspace-aware project opener. The
/// [tabsForId] hook is injected by the consumer site
/// (`ViewerScaffold`) which has access to `WorkspaceRoot.of(context)`.
final Provider<
  OpenProjectInWorkspace Function(ProviderContainer Function(crux.TabId))
>
openProjectInWorkspaceProvider =
    Provider<
      OpenProjectInWorkspace Function(ProviderContainer Function(crux.TabId))
    >((ref) {
      return (tabsForId) => OpenProjectInWorkspace(
        ref: ref,
        tabsForId: tabsForId,
      );
    });
