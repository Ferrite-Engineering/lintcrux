// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/lintcrux_tab_payload.dart';
import 'package:lintcrux/features/import_viewer/services/sarif_import_flow.dart';
import 'package:lintcrux/features/project/providers/project_picker_provider.dart';
import 'package:lintcrux/features/project/services/open_project_feedback.dart';
import 'package:lintcrux/features/project/services/open_project_service.dart';
import 'package:lintcrux/features/workspace/providers/recent_projects_provider.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/features/workspace/services/open_project_in_workspace.dart';
import 'package:lintcrux/features/workspace/widgets/empty_canvas_content.dart';
import 'package:lintcrux/features/workspace/widgets/lintcrux_status_bar.dart';
import 'package:lintcrux/features/workspace/widgets/lintcrux_toolbar.dart';
import 'package:lintcrux/features/workspace/widgets/lintcrux_viewer_tab_bar_strings.dart';
import 'package:lintcrux/features/workspace/widgets/project_tab_content.dart';
import 'package:lintcrux/features/workspace/widgets/workspace_root.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/project/project_file_codec.dart';
import 'package:lintcrux/services/project/project_file_service.dart';
import 'package:lintcrux/services/telemetry/telemetry_event_catalog.dart';
import 'package:lintcrux/shared/platform/reveal_tab_file.dart';
import 'package:path/path.dart' as p;

/// Main routed scaffold for the LintCrux workspace.
///
/// Renders an [crux.PaneHost] hosting one or two panes of project
/// tabs. When the workspace has zero tabs, the [crux.PaneHost]
/// renders [EmptyCanvasContent] instead — with primary actions
/// wired through this scaffold's `_handle*` methods so the empty
/// canvas can open projects / sessions / workspaces without
/// re-implementing the file-picker logic.
///
/// Reads the per-tab and per-pane container managers from the
/// surrounding [WorkspaceRoot] via [WorkspaceRoot.of] and hands them
/// to [crux.PaneHost].
class ViewerScaffold extends ConsumerWidget {
  /// Creates a [ViewerScaffold].
  const ViewerScaffold({super.key});

  Future<void> _handleOpenProject(BuildContext context, WidgetRef ref) async {
    final picker = ref.read(projectPickerProvider);
    final l10n = L10N.of(context);
    final String? path;
    try {
      path = await picker.pickProjectFile(
        confirmButtonText: l10n.filePickerOpenProjectButton,
        typeLabel: l10n.filePickerTypeProjectLabel,
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      showCruxErrorSnack(context, l10n.filePickerFailed('$error'));
      return;
    }
    if (path == null || !context.mounted) return;
    final opener = ref.read(openProjectInWorkspaceProvider)(
      WorkspaceRoot.of(context).tabs.containerFor,
    );
    final result = await opener.openProject(path);
    if (!context.mounted) return;
    showOpenProjectOutcome(context, result);
  }

  Future<void> _handleOpenSession(BuildContext context, WidgetRef ref) async {
    final picker = ref.read(projectPickerProvider);
    final l10n = L10N.of(context);
    final String? path;
    try {
      path = await picker.pickSessionFile(
        confirmButtonText: l10n.filePickerOpenSessionButton,
        typeLabel: l10n.filePickerTypeSessionLabel,
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      showCruxErrorSnack(context, l10n.filePickerFailed('$error'));
      return;
    }
    if (path == null || !context.mounted) return;
    final opener = ref.read(openProjectInWorkspaceProvider)(
      WorkspaceRoot.of(context).tabs.containerFor,
    );
    final result = await opener.openSession(path);
    if (!context.mounted) return;
    if (result is OpenProjectFailure) {
      showCruxErrorSnack(context, result.message);
    }
  }

  Future<void> _handleOpenWorkspace(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final picker = ref.read(projectPickerProvider);
    final l10n = L10N.of(context);
    final String? path;
    try {
      path = await picker.pickWorkspaceFile(
        confirmButtonText: l10n.filePickerOpenWorkspaceButton,
        typeLabel: l10n.filePickerTypeWorkspaceLabel,
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      showCruxErrorSnack(context, l10n.filePickerFailed('$error'));
      return;
    }
    if (path == null || !context.mounted) return;
    final opener = ref.read(openProjectInWorkspaceProvider)(
      WorkspaceRoot.of(context).tabs.containerFor,
    );
    final error = await opener.openWorkspace(path);
    if (!context.mounted) return;
    if (error != null) {
      showCruxErrorSnack(context, l10n.workspaceLoadFailed(error));
    }
  }

  Future<void> _handleNewProject(BuildContext context, WidgetRef ref) async {
    final picker = ref.read(projectPickerProvider);
    final l10n = L10N.of(context);
    final String? path;
    try {
      path = await picker.pickSaveProjectFile(
        confirmButtonText: l10n.filePickerCreateProjectButton,
        typeLabel: l10n.filePickerTypeProjectLabel,
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      showCruxErrorSnack(context, l10n.filePickerFailed('$error'));
      return;
    }
    if (path == null || !context.mounted) return;
    // Construct a minimal LintProject seeded from the chosen save
    // location: name from the basename, rootPath from the parent
    // directory. The user opens project Settings later to add source
    // files / enabled engines / per-engine options.
    final normalizedPath = path.endsWith('.lintcrux') ? path : '$path.lintcrux';
    final project = LintProject(
      name: p.basenameWithoutExtension(normalizedPath),
      rootPath: p.dirname(normalizedPath),
    );
    const service = ProjectFileService();
    try {
      await service.write(normalizedPath, project);
    } on ProjectFileException catch (e) {
      if (!context.mounted) return;
      showCruxErrorSnack(context, e.message);
      return;
    }
    if (!context.mounted) return;
    final opener = ref.read(openProjectInWorkspaceProvider)(
      WorkspaceRoot.of(context).tabs.containerFor,
    );
    final result = await opener.openProject(normalizedPath);
    if (!context.mounted) return;
    if (result is OpenProjectFailure) {
      showCruxErrorSnack(context, result.message);
    }
  }

  Future<void> _handleOpenRecentProject(
    BuildContext context,
    WidgetRef ref,
    String path,
  ) async {
    final opener = ref.read(openProjectInWorkspaceProvider)(
      WorkspaceRoot.of(context).tabs.containerFor,
    );
    final result = await opener.openProject(path);
    if (result is OpenProjectFailure) {
      // A recent entry whose file no longer opens is dropped, so the list
      // does not keep offering it.
      ref.read(recentProjectsListProvider.notifier).remove(path);
    } else {
      // The third `project.opened` telemetry source.
      ref
          .read(telemetryServiceProvider)
          .record(
            TelemetryEvent(
              'project.opened',
              properties: <String, Object?>{
                'source': telemetryEnumToken(ProjectOpenSource.recent),
              },
            ),
          );
    }
    if (!context.mounted) return;
    if (result is OpenProjectFailure) {
      showCruxErrorSnack(context, result.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = WorkspaceRoot.of(context);
    final l10n = L10N.of(context);
    // VS Code-style chrome (matching WaveCrux): the tier-1 action toolbar is a
    // left-aligned strip directly below the custom window title bar — NOT a
    // Material AppBar. The app name lives in the OS window title / taskbar, so
    // there is no in-window title band; the toolbar sits flush above the tab
    // strip. Completes the three-tier action surface (toolbar + menu bar +
    // palette).
    return Scaffold(
      // Keyboard regions (F6 / Shift+F6) and lost-focus recovery. The
      // screen-level `Actions` that handle every `ShortcutActionIntent` sit
      // above the router (`ShortcutManagerWidget` in `app.dart`), so focus
      // this scope restores is always within reach of them: focus stranded
      // on a bare scope after a native file dialog, or after the toolbar or
      // the empty canvas is rebuilt away, would otherwise leave every screen
      // shortcut dead and a screen reader silent.
      body: CruxFocusRegionScope(
        child: Column(
          children: [
            // The toolbar names its own region ("Toolbar").
            const CruxFocusRegion(child: LintcruxToolbar()),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: crux.PaneHost<LintcruxTabPayload>(
                      provider: workspaceProvider,
                      tabs: scope.tabs,
                      panes: scope.panes,
                      strings: LintcruxViewerTabBarStrings(l10n),
                      // Match WaveCrux/NetCrux/SimCrux: only show the
                      // tab-strip scroll chevrons when the strip actually
                      // overflows. Otherwise both chevrons render as
                      // permanent dead click targets, inconsistent with the
                      // other three apps and a needless semantics surface for
                      // the a11y-bridge crash class.
                      autoHideScrollChevrons: true,
                      // Match WaveCrux (canonical): tab chips are filename + X
                      // only — no leading drag-handle icon. The shared
                      // `ViewerTabBar` only renders the drag handle when
                      // `useDragHandle` is true (PaneHost's default), so opt
                      // out here for parity with WaveCrux/NetCrux/SimCrux.
                      useDragHandle: false,
                      // Full-path hover tooltip + monospace context-menu
                      // header + platform Reveal (suite tab-bar canon).
                      tabFilePath: (tab) => tab.payload.projectPath,
                      onRevealTab: revealTabFile,
                      // The start screen is where lost focus goes back to.
                      // It is not inside a `CruxIdeLayout`, whose panes are
                      // regions of their own, so it is made one here; the
                      // canvas names the region after its title.
                      emptyCanvasContent: CruxFocusRegion(
                        primary: true,
                        child: EmptyCanvasContent(
                          onOpenProject: () => _handleOpenProject(context, ref),
                          onOpenSession: () => _handleOpenSession(context, ref),
                          onOpenWorkspace: () =>
                              _handleOpenWorkspace(context, ref),
                          onNewProject: () =>
                              unawaited(_handleNewProject(context, ref)),
                          onImportSarif: () =>
                              unawaited(runSarifImportFlow(context, ref)),
                          onOpenRecentProject: (path) {
                            // Fire-and-forget — the EmptyCanvasContent
                            // callback is void-returning and there is no
                            // meaningful "in flight" UI state to surface at
                            // the empty-canvas level.
                            unawaited(
                              _handleOpenRecentProject(context, ref, path),
                            );
                          },
                        ),
                      ),
                      tabContentBuilder: (ctx, tab) =>
                          const ProjectTabContent(),
                    ),
                  ),
                ],
              ),
            ),
            // Window-bottom status bar: active tab's project + live
            // violation summary on the shared cross-suite CruxStatusBar
            // chrome. Its own keyboard region, so F6 reaches it.
            const CruxFocusRegion(child: LintcruxStatusBar()),
          ],
        ),
      ),
    );
  }
}
