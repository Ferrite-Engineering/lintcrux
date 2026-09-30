// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/workspace/named_workspace_test.dart
//
// Verification driver for Verification Guide §6.5.5 (Named workspace
// files). Drives the live `saveAs` / `resetWorkspace` / `loadFrom`
// notifier path — the same code `File → Save Workspace As…` / `Open
// Workspace…` invoke — and asserts a `.lintcrux-workspace` file
// round-trips the open tabs back into the live workspace.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lintcrux/domain/models/lintcrux_tab_payload.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'save → reset → open round-trips two tabs (guide §6.5.5)',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('lintcrux_named_ws_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final wsPath = '${dir.path}/example.lintcrux-workspace';

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

      // Save the named workspace.
      await notifier.saveAs(wsPath);
      expect(
        File(wsPath).existsSync(),
        isTrue,
        reason: 'Save Workspace As… must write the chosen file',
      );

      // Reset to the empty-canvas state.
      await notifier.resetWorkspace();
      await pumpUntil(tester, () => tabCount(tester) == 0);
      expect(tabCount(tester), 0);

      // Open the named workspace — both tabs return.
      await notifier.loadFrom(wsPath);
      await pumpUntil(tester, () => tabCount(tester) == 2);
      final ws = root.read(workspaceProvider).value!;
      expect(
        ws.tabs.map((t) => t.displayName).toSet(),
        containsAll(<String>['alpha', 'beta']),
      );

      expect(tester.takeException(), isNull);
    },
  );
}
