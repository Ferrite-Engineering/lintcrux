// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/workspace/session_open_replay_test.dart
//
// Real-app "File → Open Session…" journey: a `.lintcrux-session` file
// referencing a `.lintcrux` project is opened through the actual
// empty-canvas button + `OpenProjectInWorkspace.openSession` seam, and
// its filter/sort/view-mode state replays onto the new tab's
// `violationTableStateProvider` (not just onto a directly-invoked
// service, as the unit test in
// `test/features/workspace/services/open_project_in_workspace_test.dart`
// already covers).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/session/lintcrux_session.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';
import 'package:lintcrux/features/project/providers/project_picker_provider.dart';
import 'package:lintcrux/features/project/services/project_picker.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/features/workspace/widgets/workspace_root.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/session/session_service.dart';

import '../helpers/app_driver.dart';

/// Returns [sessionPath] from `pickSessionFile` regardless of the
/// confirm-button / type-label arguments, simulating the user
/// selecting the fixture session file in the OS picker.
class _FixedSessionPicker extends ProjectPicker {
  const _FixedSessionPicker(this.sessionPath);
  final String sessionPath;

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
    'Open Session… loads the referenced project and replays its '
    'filter/sort state onto the new tab',
    (tester) async {
      tolerateKnownFirstBuildWart();
      final dir = Directory.systemTemp.createTempSync(
        'lintcrux_session_replay_',
      );
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // Best-effort cleanup.
        }
      });

      final projectPath = await createFixtureProject(dir);
      final session = LintcruxSession(
        projectPath: projectPath,
        activeSeverities: const {Severity.error},
        activeEngineIds: const {kSeededFixtureEngineId},
        ruleSubstring: 'UNUSED',
        fileGlob: '*.sv',
        sortColumn: ViolationTableColumn.file,
        sortAscending: false,
      );
      final sessionPath = '${dir.path}/demo.lintcrux-session';
      await const SessionService().save(sessionPath, session);

      await bootLintcrux(
        tester,
        extraOverrides: [
          projectPickerProvider.overrideWithValue(
            _FixedSessionPicker(sessionPath),
          ),
        ],
      );

      final l10n = L10N.of(tester.element(find.byType(WorkspaceRoot)));
      await tester.tap(find.text(l10n.emptyCanvasOpenSessionButton));
      final opened = await pumpUntil(tester, () => tabCount(tester) == 1);
      expect(opened, isTrue, reason: 'session open never produced a tab');

      final root = rootContainer(tester);
      final workspace = root.read(workspaceProvider).value!;
      final tab = workspaceRootState(
        tester,
      ).tabs.containerFor(workspace.tabs.single.id);
      // Wait on the session replay itself (not just the project load):
      // `openSession` continues mutating the table-state provider and
      // the tab payload after `currentProjectProvider` is already
      // non-null, so polling project-load alone can observe the tab
      // before its filter/sort state has replayed.
      await pumpUntil(
        tester,
        () =>
            tab.read(currentProjectProvider) != null &&
            tab.read(violationTableStateProvider).ruleSubstring == 'UNUSED',
      );

      final tableState = tab.read(violationTableStateProvider);
      expect(tableState.ruleSubstring, 'UNUSED');
      expect(tableState.fileGlob, '*.sv');
      expect(tableState.severities, {Severity.error});
      expect(tableState.engineIds, {kSeededFixtureEngineId});
      expect(tableState.sortColumn, ViolationTableColumn.file);
      expect(tableState.sortAscending, isFalse);

      // The session export path is mirrored onto the tab's persisted
      // payload — the workspace document now knows this tab originated
      // from a session import.
      await tester.pump();
      final persistedTab = root.read(workspaceProvider).value!.tabs.single;
      expect(persistedTab.payload.sessionExportPath, sessionPath);

      expect(tester.takeException(), isNull);
    },
  );
}
