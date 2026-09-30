// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_settings/crux_settings.dart';
import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/lintcrux_tab_payload.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/services/persistence/restore_tabs_settings_codec.dart';
import 'package:lintcrux/services/persistence/restore_tabs_settings_provider.dart';
import 'package:lintcrux/services/workspace/lintcrux_workspace_codec.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../support/telemetry_test_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final containersToDispose = <ProviderContainer>[];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lintcrux_ws_test_');
    containersToDispose.clear();
  });

  tearDown(() async {
    // Dispose containers BEFORE removing the temp dir so the package's
    // best-effort "flush on dispose" save doesn't race a vanished
    // directory and noise up the test output with PathNotFoundException
    // log lines.
    for (final c in containersToDispose.reversed) {
      c.dispose();
    }
    containersToDispose.clear();
    if (tempDir.existsSync()) {
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        // Windows can briefly hold an OS-level handle on a just-flushed
        // workspace file after container dispose, so recursive delete throws
        // PathAccessException ("being used by another process"). The deletion
        // is best-effort cleanup — the OS reclaims the temp dir later.
      }
    }
  });

  WorkspaceService buildService() {
    return WorkspaceService(
      codec: const LintcruxWorkspaceCodec(),
      directoryFactory: () async => tempDir,
    );
  }

  ProviderContainer buildContainer(WorkspaceService service) {
    final container = ProviderContainer(
      overrides: [
        ...telemetryDeclinedOverrides(),
        workspaceServiceProvider.overrideWithValue(service),
      ],
    );
    containersToDispose.add(container);
    return container;
  }

  test('build() returns an empty workspace when no document exists', () async {
    final service = buildService();
    final container = buildContainer(service);
    final ws = await container.read(workspaceProvider.future);
    expect(ws.isEmpty, isTrue);
    expect(ws.panes.length, 1);
  });

  test('openTab persists the new tab and surfaces it in state', () async {
    final service = buildService();
    final container = buildContainer(service);
    await container.read(workspaceProvider.future);
    final notifier = container.read(workspaceProvider.notifier);
    await notifier.openTab(
      displayName: 'cpu_core',
      payload: const LintcruxTabPayload(
        projectPath: '/p/cpu_core.lintcrux',
      ),
    );
    final ws = container.read(workspaceProvider).requireValue;
    expect(ws.tabs.length, 1);
    expect(ws.tabs.single.displayName, 'cpu_core');
    expect(ws.tabs.single.payload.projectPath, '/p/cpu_core.lintcrux');
  });

  test('closeTab removes the tab and leaves the pane intact', () async {
    final service = buildService();
    final container = buildContainer(service);
    await container.read(workspaceProvider.future);
    final notifier = container.read(workspaceProvider.notifier);
    final tabId = await notifier.openTab(
      displayName: 'a',
      payload: const LintcruxTabPayload(projectPath: '/p/a.lintcrux'),
    );
    await notifier.closeTab(tabId);
    final ws = container.read(workspaceProvider).requireValue;
    expect(ws.tabs, isEmpty);
    expect(ws.panes.length, 1);
  });

  test('splitPaneRight produces a second pane', () async {
    final service = buildService();
    final container = buildContainer(service);
    await container.read(workspaceProvider.future);
    final notifier = container.read(workspaceProvider.notifier);
    await notifier.openTab(
      displayName: 'a',
      payload: const LintcruxTabPayload(projectPath: '/p/a.lintcrux'),
    );
    final newPane = await notifier.splitPaneRight();
    final ws = container.read(workspaceProvider).requireValue;
    expect(ws.panes.length, 2);
    expect(ws.activePaneId, equals(newPane));
  });

  test('payload mutation via updateTabPayload is reflected in state', () async {
    final service = buildService();
    final container = buildContainer(service);
    await container.read(workspaceProvider.future);
    final notifier = container.read(workspaceProvider.notifier);
    final tabId = await notifier.openTab(
      displayName: 'a',
      payload: const LintcruxTabPayload(projectPath: '/p/a.lintcrux'),
    );
    await notifier.updateTabPayload(
      tabId,
      (p) => p.copyWith(selectedRuleId: 'verilator/UNUSED'),
    );
    final ws = container.read(workspaceProvider).requireValue;
    expect(ws.tabs.single.payload.selectedRuleId, 'verilator/UNUSED');
  });

  test('save → load round-trips through disk', () async {
    final service = buildService();
    final container1 = buildContainer(service);
    await container1.read(workspaceProvider.future);
    final notifier1 = container1.read(workspaceProvider.notifier);
    await notifier1.openTab(
      displayName: 'a',
      payload: const LintcruxTabPayload(
        projectPath: '/p/a.lintcrux',
        savedFilterPresetName: 'release',
      ),
    );
    await notifier1.flushPendingSave();

    // New container, same service → reads workspace.json from disk.
    final container2 = buildContainer(service);
    final ws2 = await container2.read(workspaceProvider.future);
    expect(ws2.tabs.length, 1);
    expect(ws2.tabs.single.payload.projectPath, '/p/a.lintcrux');
    expect(ws2.tabs.single.payload.savedFilterPresetName, 'release');
  });

  test('resetWorkspace returns to empty', () async {
    final service = buildService();
    final container = buildContainer(service);
    await container.read(workspaceProvider.future);
    final notifier = container.read(workspaceProvider.notifier);
    await notifier.openTab(
      displayName: 'a',
      payload: const LintcruxTabPayload(projectPath: '/p/a.lintcrux'),
    );
    await notifier.openTab(
      displayName: 'b',
      payload: const LintcruxTabPayload(projectPath: '/p/b.lintcrux'),
    );
    expect(
      container.read(workspaceProvider).requireValue.tabs.length,
      2,
    );
    await notifier.resetWorkspace();
    final ws = container.read(workspaceProvider).requireValue;
    expect(ws.isEmpty, isTrue);
    expect(ws.panes.length, 1);
  });

  test('typedef Workspace binds to LintcruxTabPayload', () {
    // Smoke check — typedef resolves at compile time. The cast verifies
    // the binding is the expected one.
    final pane = crux.WorkspacePane(id: crux.PaneId.generate());
    final ws = Workspace(
      tabs: const [],
      panes: [pane],
      activePaneId: pane.id,
    );
    expect(ws, isA<crux.Workspace<LintcruxTabPayload>>());
  });

  // ───────────────────────────────────────────────────────────────────────
  // Tab dedupe (beta regression).
  //
  // Provider-level `test()`s over a `ProviderContainer`, not `testWidgets`:
  // the widget harness can only settle a launch when `workspace.json` is
  // absent, which is precisely the case this bug is *not* about.
  // ───────────────────────────────────────────────────────────────────────
  group('openTab dedupe', () {
    late String projectPath;

    setUp(() {
      projectPath = p.join(tempDir.path, 'riscv-soc.lintcrux');
      File(projectPath).writeAsStringSync('{}');
    });

    Future<ProviderContainer> bootedContainer() async {
      final container = buildContainer(buildService());
      await container.read(workspaceProvider.future);
      return container;
    }

    test('a second open of the same path focuses the existing tab', () async {
      final container = await bootedContainer();
      final notifier = container.read(workspaceProvider.notifier);
      final first = await notifier.openTab(
        displayName: 'riscv-soc',
        payload: LintcruxTabPayload(projectPath: projectPath),
      );
      final second = await notifier.openTab(
        displayName: 'riscv-soc',
        payload: LintcruxTabPayload(projectPath: projectPath),
      );
      expect(second, first);
      expect(container.read(workspaceProvider).requireValue.tabs.length, 1);
    });

    for (final entry in <String, String Function(String, Directory)>{
      'a relative path': (path, _) => p.relative(path),
      'a `..` segment': (path, dir) =>
          p.join(dir.path, 'sub', '..', p.basename(path)),
    }.entries) {
      test('${entry.key} dedupes against the absolute one', () async {
        final container = await bootedContainer();
        final notifier = container.read(workspaceProvider.notifier);
        final first = await notifier.openTab(
          displayName: 'riscv-soc',
          payload: LintcruxTabPayload(projectPath: projectPath),
        );
        final second = await notifier.openTab(
          displayName: 'riscv-soc',
          payload: LintcruxTabPayload(
            projectPath: entry.value(projectPath, tempDir),
          ),
        );
        expect(second, first);
        expect(container.read(workspaceProvider).requireValue.tabs.length, 1);
      });
    }

    test('dedupes against a tab rehydrated from disk', () async {
      // The actual bug shape. Session one saves a tab; session two relaunches
      // with the project as a CLI argument and must focus the restored tab,
      // not stack a second copy of it. Seven relaunches produced seven tabs.
      final first = buildContainer(buildService());
      await first.read(workspaceProvider.future);
      await first
          .read(workspaceProvider.notifier)
          .openTab(
            displayName: 'riscv-soc',
            payload: LintcruxTabPayload(projectPath: projectPath),
          );
      await first.read(workspaceProvider.notifier).flushPendingSave();
      first.dispose();
      containersToDispose.remove(first);

      // Session two: fresh container over the same directory, so the
      // workspace document is loaded from disk.
      final second = buildContainer(buildService());
      final restored = await second.read(workspaceProvider.future);
      expect(restored.tabs.length, 1, reason: 'the document must rehydrate');

      // The CLI hands over a relative spelling — nothing canonicalises it
      // on the way in.
      await second
          .read(workspaceProvider.notifier)
          .openTab(
            displayName: 'riscv-soc',
            payload: LintcruxTabPayload(projectPath: p.relative(projectPath)),
          );
      expect(second.read(workspaceProvider).requireValue.tabs.length, 1);
    });

    test('a different project still opens its own tab', () async {
      final container = await bootedContainer();
      final other = p.join(tempDir.path, 'other.lintcrux');
      File(other).writeAsStringSync('{}');
      final notifier = container.read(workspaceProvider.notifier);
      await notifier.openTab(
        displayName: 'riscv-soc',
        payload: LintcruxTabPayload(projectPath: projectPath),
      );
      await notifier.openTab(
        displayName: 'other',
        payload: LintcruxTabPayload(projectPath: other),
      );
      expect(container.read(workspaceProvider).requireValue.tabs.length, 2);
    });

    test('empty-canvas tabs never fold together', () async {
      final container = await bootedContainer();
      final notifier = container.read(workspaceProvider.notifier);
      final a = await notifier.openTab(
        displayName: 'untitled',
        payload: const LintcruxTabPayload(projectPath: ''),
      );
      final b = await notifier.openTab(
        displayName: 'untitled',
        payload: const LintcruxTabPayload(projectPath: ''),
      );
      expect(b, isNot(a));
      expect(container.read(workspaceProvider).requireValue.tabs.length, 2);
    });

    test('dedupe: false still opens a second view of one project', () async {
      final container = await bootedContainer();
      final notifier = container.read(workspaceProvider.notifier);
      final a = await notifier.openTab(
        displayName: 'riscv-soc',
        payload: LintcruxTabPayload(projectPath: projectPath),
      );
      final b = await notifier.openTab(
        displayName: 'riscv-soc',
        payload: LintcruxTabPayload(projectPath: projectPath),
        dedupe: false,
      );
      expect(b, isNot(a));
      expect(container.read(workspaceProvider).requireValue.tabs.length, 2);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // The launch restore gate (beta regression).
  // ───────────────────────────────────────────────────────────────────────
  group('shouldRestoreOnLaunch', () {
    late String projectPath;

    setUp(() {
      projectPath = p.join(tempDir.path, 'riscv-soc.lintcrux');
      File(projectPath).writeAsStringSync('{}');
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    /// Writes a one-tab workspace document into [tempDir] and returns it.
    Future<void> seedDocument() async {
      final seeder = buildContainer(buildService());
      await seeder.read(workspaceProvider.future);
      await seeder
          .read(workspaceProvider.notifier)
          .openTab(
            displayName: 'riscv-soc',
            payload: LintcruxTabPayload(projectPath: projectPath),
          );
      await seeder.read(workspaceProvider.notifier).flushPendingSave();
      seeder.dispose();
      containersToDispose.remove(seeder);
    }

    Future<ProviderContainer> relaunch({required bool? preference}) async {
      // `bootstrap` resolves the preference before `runApp` and overrides the
      // decision provider with the answer; this mirrors that, going through
      // the same `loadRestoreTabsOnLaunch` the production path uses so the
      // key lookup and the failure fallback are both exercised.
      final prefs = await SharedPreferences.getInstance();
      if (preference == null) {
        await prefs.remove(RestoreTabsSettingsCodec.prefsKey);
      } else {
        await prefs.setBool(RestoreTabsSettingsCodec.prefsKey, preference);
      }
      final decision = await loadRestoreTabsOnLaunch(
        service: SettingsService<bool>(
          const RestoreTabsSettingsCodec(),
          prefsOverride: prefs,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          ...telemetryDeclinedOverrides(),
          workspaceServiceProvider.overrideWithValue(buildService()),
          launchRestoreDecisionProvider.overrideWithValue(decision),
        ],
      );
      containersToDispose.add(container);
      return container;
    }

    test('restores the document when the preference is unset', () async {
      await seedDocument();
      final container = await relaunch(preference: null);
      final ws = await container.read(workspaceProvider.future);
      expect(ws.tabs.length, 1);
      expect(
        container.read(workspaceProvider.notifier).launchRestoreDeclined,
        isFalse,
      );
    });

    test('restores the document when the preference is on', () async {
      await seedDocument();
      final container = await relaunch(preference: true);
      final ws = await container.read(workspaceProvider.future);
      expect(ws.tabs.length, 1);
    });

    test('declines the restore when the preference is off', () async {
      // The reported defect: `flutter.settings.restoreTabsOnLaunch = false`
      // restored the tabs anyway, because nothing read it.
      await seedDocument();
      final container = await relaunch(preference: false);
      final ws = await container.read(workspaceProvider.future);
      expect(ws.isEmpty, isTrue);
      expect(
        container.read(workspaceProvider.notifier).launchRestoreDeclined,
        isTrue,
      );
    });

    test('declining leaves the document on disk', () async {
      await seedDocument();
      final declined = await relaunch(preference: false);
      expect((await declined.read(workspaceProvider.future)).isEmpty, isTrue);
      declined.dispose();
      containersToDispose.remove(declined);

      // Flipping the preference back on restores the session that was there
      // — the whole point of declining rather than clearing.
      final restored = await relaunch(preference: true);
      final ws = await restored.read(workspaceProvider.future);
      expect(ws.tabs.length, 1);
      expect(ws.tabs.single.payload.projectPath, projectPath);
    });

    test('restores when the settings read throws', () async {
      // Losing a session because a *preference* was unreadable is the worse
      // failure, so a throwing settings backend must resolve to restoring.
      await seedDocument();
      final decision = await loadRestoreTabsOnLaunch(
        service: const _ThrowingSettingsService(),
      );
      expect(decision, isTrue);

      final container = ProviderContainer(
        overrides: [
          ...telemetryDeclinedOverrides(),
          workspaceServiceProvider.overrideWithValue(buildService()),
          launchRestoreDecisionProvider.overrideWithValue(decision),
        ],
      );
      containersToDispose.add(container);
      final ws = await container
          .read(workspaceProvider.future)
          .timeout(const Duration(seconds: 5));
      expect(ws.tabs.length, 1);
    });

    test('the gate never touches storage from inside the notifier', () async {
      // The regression that cost two products a day of timing-out widget
      // tests: `SharedPreferences.getInstance()` replies on the real event
      // loop, so awaiting it on the launch path hangs any fake-async test.
      // A container with no settings override at all must still resolve.
      await seedDocument();
      final container = ProviderContainer(
        overrides: [
          ...telemetryDeclinedOverrides(),
          workspaceServiceProvider.overrideWithValue(buildService()),
          restoreTabsSettingsServiceProvider.overrideWithValue(
            const _ThrowingSettingsService(),
          ),
        ],
      );
      containersToDispose.add(container);
      final ws = await container
          .read(workspaceProvider.future)
          .timeout(const Duration(seconds: 5));
      // Default decision: restore.
      expect(ws.tabs.length, 1);
    });
  });
}

/// A settings service whose load always throws — the shape a missing
/// platform channel produces.
class _ThrowingSettingsService extends SettingsService<bool> {
  const _ThrowingSettingsService() : super(const RestoreTabsSettingsCodec());

  @override
  Future<bool> load() async => throw const _NoBackend();

  @override
  Future<void> save(bool settings) async => throw const _NoBackend();
}

class _NoBackend implements Exception {
  const _NoBackend();
}
