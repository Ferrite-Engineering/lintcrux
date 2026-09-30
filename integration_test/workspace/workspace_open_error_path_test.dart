// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/workspace/workspace_open_error_path_test.dart
//
// Real-app error-path journeys for `OpenProjectInWorkspace.openWorkspace`
// and `.openSession`, driven through the actual empty-canvas buttons
// (not a direct service call, as the unit test in
// `test/features/workspace/services/open_project_in_workspace_test.dart`
// already covers):
//
// 1. A named `.lintcrux-workspace` referencing two tabs, one of whose
//    project file has since been deleted, skips only that tab instead
//    of aborting the whole load.
// 2. Opening a `.lintcrux-session` that points at a nonexistent file
//    surfaces the real error message via a snackbar rather than
//    failing silently.

import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lintcrux/domain/models/lintcrux_tab_payload.dart';
import 'package:lintcrux/features/project/providers/project_picker_provider.dart';
import 'package:lintcrux/features/project/services/project_picker.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/features/workspace/widgets/workspace_root.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/workspace/lintcrux_workspace_codec.dart';
import 'package:path/path.dart' as p;

import '../helpers/app_driver.dart';

/// Returns a fixed path from whichever picker method the test needs,
/// regardless of the confirm-button / type-label arguments.
class _FixedPathPicker extends ProjectPicker {
  const _FixedPathPicker({this.workspacePath, this.sessionPath});
  final String? workspacePath;
  final String? sessionPath;

  @override
  Future<String?> pickWorkspaceFile({
    required String confirmButtonText,
    required String typeLabel,
  }) async => workspacePath;

  @override
  Future<String?> pickSessionFile({
    required String confirmButtonText,
    required String typeLabel,
  }) async => sessionPath;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'Open Workspace… skips a tab whose project file is missing instead '
    'of aborting the whole load',
    (tester) async {
      tolerateKnownFirstBuildWart();
      final dir = Directory.systemTemp.createTempSync(
        'lintcrux_ws_error_path_',
      );
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // Best-effort cleanup.
        }
      });
      final wsPath = p.join(dir.path, 'team.lintcrux-workspace');

      // Build the two fixture project files and a `.lintcrux-workspace`
      // document referencing them directly via `WorkspaceService` —
      // deliberately NOT through a real "File → Open" in this process,
      // so neither tab's per-tab `ProviderContainer` exists yet when
      // the app boots. (Pre-opening them first — e.g. via
      // `openFixtureProject` then `resetWorkspace()` — leaves stale,
      // already-hydrated containers cached in `TabContainerManager`
      // under the reopened tab's *original* id, since a workspace
      // reset clears the tab list but not that cache; reopening would
      // then observe the old in-memory state rather than genuinely
      // reloading from disk, which is not what a real cold start does.)
      final pathA = await createFixtureProject(dir, name: 'alpha');
      final pathB = await createFixtureProject(dir, name: 'beta');
      final paneId = crux.PaneId.generate();
      final tabAId = crux.TabId.generate();
      final tabBId = crux.TabId.generate();
      final workspace = Workspace(
        tabs: [
          WorkspaceTab(
            id: tabAId,
            displayName: 'alpha',
            paneId: paneId,
            payload: LintcruxTabPayload(projectPath: pathA),
          ),
          WorkspaceTab(
            id: tabBId,
            displayName: 'beta',
            paneId: paneId,
            payload: LintcruxTabPayload(projectPath: pathB),
          ),
        ],
        panes: [crux.WorkspacePane(id: paneId, activeTabId: tabAId)],
        activePaneId: paneId,
      );
      await WorkspaceService(
        codec: const LintcruxWorkspaceCodec(),
      ).saveToPath(wsPath, workspace);

      // Delete tab B's project file AFTER the workspace document is
      // written, so opening it hits the per-tab skip-on-error branch.
      await File(pathB).delete();

      await bootLintcrux(
        tester,
        extraOverrides: [
          projectPickerProvider.overrideWithValue(
            _FixedPathPicker(workspacePath: wsPath),
          ),
        ],
      );

      final l10n = L10N.of(tester.element(find.byType(WorkspaceRoot)));
      await tester.tap(find.text(l10n.emptyCanvasOpenWorkspaceButton));
      final opened = await pumpUntil(tester, () => tabCount(tester) == 2);
      expect(opened, isTrue, reason: 'workspace open never produced 2 tabs');

      final scope = workspaceRootState(tester);
      final tabA = scope.tabs.containerFor(tabAId);
      final tabB = scope.tabs.containerFor(tabBId);
      await pumpUntil(
        tester,
        () => tabA.read(currentProjectProvider) != null,
      );

      expect(tabA.read(currentProjectProvider)?.name, 'alpha');
      // Skipped: the tab still exists in the opened workspace document
      // but its per-tab container never received a project, because
      // `beta.lintcrux` no longer exists on disk.
      expect(tabB.read(currentProjectProvider), isNull);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Open Session… on a missing file surfaces the real error via a '
    'snackbar instead of failing silently',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync(
        'lintcrux_session_error_path_',
      );
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // Best-effort cleanup.
        }
      });
      final missingSessionPath = p.join(dir.path, 'gone.lintcrux-session');

      await bootLintcrux(
        tester,
        extraOverrides: [
          projectPickerProvider.overrideWithValue(
            _FixedPathPicker(sessionPath: missingSessionPath),
          ),
        ],
      );

      final l10n = L10N.of(tester.element(find.byType(WorkspaceRoot)));
      await tester.tap(find.text(l10n.emptyCanvasOpenSessionButton));
      final errorShown = await pumpUntil(
        tester,
        () => find
            .textContaining('Session file does not exist')
            .evaluate()
            .isNotEmpty,
      );
      expect(
        errorShown,
        isTrue,
        reason: 'missing-session error was never surfaced to the user',
      );
      // No tab was created — the failure did not silently half-succeed.
      expect(tabCount(tester), 0);

      expect(tester.takeException(), isNull);
    },
  );
}
