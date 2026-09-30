// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_descriptors.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/lintcrux_tab_payload.dart';
import 'package:lintcrux/features/workspace/providers/active_tab_action_flags_provider.dart';
import 'package:lintcrux/features/workspace/providers/lintcrux_action_context_provider.dart';
import 'package:lintcrux/features/workspace/providers/tab_overrides_factory.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/workspace/lintcrux_workspace_codec.dart';
import 'package:lintcrux/services/workspace/tab_container_manager_holder.dart';
import '../../../support/telemetry_test_store.dart';

/// Exercises the root-scope mirror against a real workspace + per-tab
/// container manager, wired the way production does it (`WorkspaceRoot`
/// publishes the manager into `tabContainerManagerHolderProvider` on the
/// ROOT container). Sibling of SimCrux's
/// `simcrux_action_context_provider_test.dart`, added while pinning the
/// 2026-07-30 SimCrux "run actions permanently disabled" regression: the
/// enablement flags must actually go TRUE when a project is open, or every
/// run action greys out for the whole session with no error anywhere.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer root;
  late crux.TabContainerManager manager;

  Future<void> setUpHarness() async {
    final tempDir = await Directory.systemTemp.createTemp('lintcrux_flags_');
    root = ProviderContainer(
      overrides: <Override>[
        ...telemetryDeclinedOverrides(),
        workspaceServiceProvider.overrideWithValue(
          WorkspaceService(
            codec: const LintcruxWorkspaceCodec(),
            directoryFactory: () async => tempDir,
          ),
        ),
      ],
    );
    manager = crux.TabContainerManager(
      rootContainer: root,
      overridesFactory: lintcruxTabOverridesFactory,
    );
    // Production parity: WorkspaceRoot.initState publishes the manager into
    // the root container's holder before any action surface builds.
    root.read(tabContainerManagerHolderProvider).manager = manager;
    addTearDown(() async {
      await root.read(workspaceProvider.notifier).flushPendingSave();
      root.dispose();
      manager.dispose();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });
    await root.read(workspaceProvider.future);
  }

  test(
    'opening a project flips hasProject true and enables the run actions '
    'at root scope',
    () async {
      await setUpHarness();
      // Keep the mirror alive the way the menu / toolbar / palette do (an
      // unlistened provider is paused and would not receive container events).
      final sub = root.listen(lintcruxActionContextProvider, (_, _) {});
      addTearDown(sub.close);

      final cold = sub.read();
      expect(cold.hasOpenTab, isFalse);
      expect(cold.hasProject, isFalse);
      expect(isActionEnabled(LintcruxAction.runAllEngines, cold), isFalse);

      // Open Project: a workspace tab is opened for the picked `.lintcrux`…
      final tabId = await root
          .read(workspaceProvider.notifier)
          .openTab(
            displayName: 'a',
            payload: const LintcruxTabPayload(projectPath: '/p/a.lintcrux'),
          );
      await Future<void>.delayed(Duration.zero);

      // …and the loaded project is published into the tab's
      // currentProjectProvider (per-tab scope), exactly as the open flow does.
      manager
          .containerFor(tabId)
          .read(currentProjectProvider.notifier)
          .load(const LintProject(name: 'a', rootPath: '/p'));
      // The mirror applies cross-container updates on a microtask; flush.
      await Future<void>.delayed(Duration.zero);

      final ctx = sub.read();
      expect(ctx.hasOpenTab, isTrue);
      expect(
        ctx.hasProject,
        isTrue,
        reason:
            'The root-scope action context must mirror the active tab’s '
            'loaded project; false here means the flags mirror cannot reach '
            'the tab container and every run action stays disabled.',
      );
      expect(isActionEnabled(LintcruxAction.runAllEngines, ctx), isTrue);
      expect(isActionEnabled(LintcruxAction.cancelRun, ctx), isFalse);

      final flags = root.read(activeTabActionFlagsProvider);
      expect(flags.hasProject, isTrue);
      expect(flags.runInProgress, isFalse);
    },
  );

  test(
    'flags stay empty (no crash) when no WorkspaceRoot has published a '
    'manager',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('lintcrux_flags_');
      final bare = ProviderContainer(
        overrides: <Override>[
          ...telemetryDeclinedOverrides(),
          workspaceServiceProvider.overrideWithValue(
            WorkspaceService(
              codec: const LintcruxWorkspaceCodec(),
              directoryFactory: () async => tempDir,
            ),
          ),
        ],
      );
      addTearDown(() async {
        await bare.read(workspaceProvider.notifier).flushPendingSave();
        bare.dispose();
        if (tempDir.existsSync()) await tempDir.delete(recursive: true);
      });
      await bare.read(workspaceProvider.future);
      final sub = bare.listen(activeTabActionFlagsProvider, (_, _) {});
      addTearDown(sub.close);
      await bare
          .read(workspaceProvider.notifier)
          .openTab(
            displayName: 'a',
            payload: const LintcruxTabPayload(projectPath: '/p/a.lintcrux'),
          );
      await Future<void>.delayed(Duration.zero);
      expect(sub.read(), const ActiveTabActionFlags());
    },
  );
}
