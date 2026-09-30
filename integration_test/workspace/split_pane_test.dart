// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/workspace/split_pane_test.dart
//
// Verification driver for Verification Guide §6.5.3 (Split-pane — tab
// between panes). Exercises the `splitPaneRight` + `moveTabToPane`
// mutation contract against the live workspace: splitting creates a
// second pane, moving a tab reassigns its `paneId`, and emptying a
// pane collapses the workspace back to a single pane.
//
// The two tabs point at REAL fixture `.lintcrux` files. They must:
// `ProjectTabContent` drops any tab whose project file will not load
// (the auto-reopened-recent-project path), so tabs backed by invented
// paths are pruned on the first frame they render and the pane
// assertions below then read an empty workspace.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lintcrux/domain/models/lintcrux_tab_payload.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:path/path.dart' as p;

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'split right then move a tab between panes (guide §6.5.3)',
    (tester) async {
      final fixtureDir = Directory.systemTemp.createTempSync(
        'lintcrux_split_pane',
      );
      addTearDown(() {
        try {
          fixtureDir.deleteSync(recursive: true);
        } on FileSystemException {
          // Best-effort cleanup.
        }
      });

      await bootLintcrux(tester);
      final alphaPath = await createFixtureProject(
        Directory(p.join(fixtureDir.path, 'alpha'))..createSync(),
        name: 'alpha',
        sources: {'rtl/a.sv': 'module a; endmodule\n'},
      );
      final betaPath = await createFixtureProject(
        Directory(p.join(fixtureDir.path, 'beta'))..createSync(),
        name: 'beta',
        sources: {'rtl/b.sv': 'module b; endmodule\n'},
      );

      final root = rootContainer(tester);
      final notifier = root.read(workspaceProvider.notifier);

      final t1 = await notifier.openTab(
        displayName: 'alpha',
        payload: LintcruxTabPayload(projectPath: alphaPath),
      );
      final t2 = await notifier.openTab(
        displayName: 'beta',
        payload: LintcruxTabPayload(projectPath: betaPath),
      );
      final bothOpen = await pumpUntil(tester, () => tabCount(tester) == 2);
      expect(bothOpen, isTrue, reason: 'both fixture tabs must open');

      // Split a new pane to the right.
      final rightPane = await notifier.splitPaneRight();
      await tester.pump();
      var ws = root.read(workspaceProvider).value!;
      expect(ws.panes, hasLength(2), reason: 'split creates a second pane');

      // Move both tabs into the right pane; the left pane then has none.
      await notifier.moveTabToPane(t1, rightPane);
      await notifier.moveTabToPane(t2, rightPane);
      await tester.pump();
      ws = root.read(workspaceProvider).value!;
      expect(
        ws.tabs.where((t) => t.paneId == rightPane),
        hasLength(2),
        reason: 'both tabs now live in the right pane',
      );

      // A pane emptied of all tabs collapses — the workspace returns to a
      // single pane (the surviving populated one).
      expect(
        ws.panes,
        hasLength(1),
        reason: 'the now-empty left pane collapses back to single-pane',
      );

      expect(tester.takeException(), isNull);
    },
  );
}
