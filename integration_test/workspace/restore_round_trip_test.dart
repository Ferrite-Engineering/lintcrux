// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/workspace/restore_round_trip_test.dart
//
// Workspace auto-save + restore round-trip. `runApp` can only run once per
// process, so "quit and relaunch" is approximated by driving the live
// workspace, flushing the debounced auto-save, and re-reading the persisted
// `workspace.json` through a fresh `WorkspaceService` — the same pattern the
// NetCrux/WaveCrux suites use.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lintcrux/domain/models/lintcrux_tab_payload.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'two opened tabs auto-persist and re-read identically',
    (tester) async {
      await bootLintcrux(tester);
      final root = rootContainer(tester);
      final notifier = root.read(workspaceProvider.notifier);

      await notifier.openTab(
        displayName: 'alpha',
        payload: const LintcruxTabPayload(projectPath: '/tmp/alpha.lintcrux'),
      );
      await notifier.openTab(
        displayName: 'beta',
        payload: const LintcruxTabPayload(projectPath: '/tmp/beta.lintcrux'),
      );
      await pumpUntil(tester, () => tabCount(tester) == 2);
      expect(tabCount(tester), 2);

      await notifier.flushPendingSave();

      final reloaded = await freshWorkspaceLoad();
      expect(reloaded.tabs, hasLength(2));
      expect(
        reloaded.tabs.map((t) => t.displayName).toSet(),
        containsAll(<String>['alpha', 'beta']),
      );
      expect(
        reloaded.tabs.map((t) => t.payload.projectPath).toSet(),
        containsAll(<String>['/tmp/alpha.lintcrux', '/tmp/beta.lintcrux']),
      );

      expect(tester.takeException(), isNull);
    },
  );
}
