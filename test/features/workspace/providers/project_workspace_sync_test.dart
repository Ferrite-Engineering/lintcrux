// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_projects/crux_projects.dart';
import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/lintcrux_tab_payload.dart';
import 'package:lintcrux/features/workspace/providers/project_workspace_sync.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/services/persistence/restore_tabs_settings_codec.dart';
import 'package:lintcrux/services/persistence/restore_tabs_settings_provider.dart';
import 'package:lintcrux/services/workspace/lintcrux_workspace_codec.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_multi_project_registry.dart';
import '../../../support/fake_path_provider.dart';
import '../../../support/telemetry_test_store.dart';

/// Polls [predicate] up to [attempts] times, yielding to the event loop
/// between checks so the fire-and-forget convergence loop (and the
/// registry's async disk writes) can settle. Returns whether it became
/// true.
Future<bool> _settleUntil(
  bool Function() predicate, {
  int attempts = 200,
}) async {
  for (var i = 0; i < attempts; i++) {
    if (predicate()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return predicate();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Defensive: this test overrides `workspaceServiceProvider` with a
  // temp-dir-backed service, but reads the real workspace/registry provider
  // graph. Installing the fake guarantees any transitive
  // application-support resolution succeeds identically on macOS, Windows,
  // and Linux under `flutter test` (the method-channel default throws
  // `MissingPluginException` on macOS/Windows).
  useFakePathProvider();

  // The Pro registry stores `p.normalize(p.absolute(path))`, and so does the
  // double, so a rooted POSIX spelling does not survive round-trip on
  // Windows: `/proj/a` becomes `C:\proj\a`. Put the synthetic paths through
  // the same transform so the payload a tab carries and the path the registry
  // records compare equal on every host.
  final alphaPath = FakeMultiProjectRegistry.canonicalize(
    '/proj/alpha.lintcrux',
  );
  final betaPath = FakeMultiProjectRegistry.canonicalize('/proj/beta.lintcrux');

  late Directory tempDir;
  final containersToDispose = <ProviderContainer>[];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lintcrux_ws_sync_test_');
    containersToDispose.clear();
  });

  tearDown(() async {
    for (final c in containersToDispose.reversed) {
      c.dispose();
    }
    containersToDispose.clear();
    if (tempDir.existsSync()) {
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        // Best-effort cleanup.
      }
    }
  });

  WorkspaceService buildService() {
    return WorkspaceService(
      codec: const LintcruxWorkspaceCodec(),
      directoryFactory: () async => tempDir,
    );
  }

  /// Anchors the sync with a real *listener*, not a `read`.
  ///
  /// Riverpod 3 pauses a provider nothing is listening to, and a paused
  /// listener's stream subscription stops receiving. The sync's
  /// registry-originated steps are driven by `projectWorkspaceProvider`'s
  /// stream, so a `container.read(projectWorkspaceSyncProvider)` harness can
  /// only ever exercise the workspace→registry direction — the registry→
  /// workspace direction silently never fires. `lib/app.dart` anchors the
  /// sync with `ref.watch` inside a build, which is a real listener; this
  /// mirrors that.
  void anchorSync(ProviderContainer container) {
    container
      ..listen(projectWorkspaceProvider, (_, _) {})
      ..listen(projectWorkspaceSyncProvider, (_, _) {}, fireImmediately: true);
  }

  ProviderContainer buildContainer(ProjectRegistry registry) {
    final container = ProviderContainer(
      overrides: [
        ...telemetryDeclinedOverrides(),
        workspaceServiceProvider.overrideWithValue(buildService()),
        projectRegistryProvider.overrideWithValue(registry),
      ],
    );
    containersToDispose.add(container);
    return container;
  }

  group('ProjectWorkspaceSync (multi-project registry)', () {
    // The multi-project contract, not the Pro implementation of it: that
    // implementation is the paid capability and no open-core test can import
    // it. The double appends on open and moves closed projects to recents,
    // which is all the sync observes.
    late FakeMultiProjectRegistry registry;

    setUp(() {
      registry = FakeMultiProjectRegistry();
    });

    test(
      'records each opened project tab into the registry and activates it',
      () async {
        final container = buildContainer(registry);
        await container.read(workspaceProvider.future);
        // Anchor the sync (installs both fireImmediately listeners).
        container.read(projectWorkspaceSyncProvider);

        final notifier = container.read(workspaceProvider.notifier);

        // Open project A through the real workspace API (what
        // OpenProjectInWorkspace.openProject drives).
        await notifier.openTab(
          displayName: 'alpha',
          payload: LintcruxTabPayload(
            projectPath: alphaPath,
          ),
        );
        final aRegistered = await _settleUntil(
          () => registry.current.openProjects.any(
            (d) => d.projectPath == alphaPath,
          ),
        );
        expect(aRegistered, isTrue, reason: 'project A never registered');

        // Open project B — a second, distinct project.
        await notifier.openTab(
          displayName: 'beta',
          payload: LintcruxTabPayload(projectPath: betaPath),
        );
        final bothRegistered = await _settleUntil(
          () => registry.current.openProjects.length == 2,
        );
        expect(
          bothRegistered,
          isTrue,
          reason: 'both projects should be registered (multi-project)',
        );

        // The active tab (B, just opened) is the active project.
        final activeAligned = await _settleUntil(
          () => registry.current.activeProject?.projectPath == betaPath,
        );
        expect(
          activeAligned,
          isTrue,
          reason: 'active project should track the active tab',
        );

        // Isolation: the two registered projects are distinct descriptors.
        final paths = registry.current.openProjects
            .map((d) => d.projectPath)
            .toSet();
        expect(
          paths,
          {alphaPath, betaPath},
        );
      },
    );

    test('closing a project tab moves it out of open projects', () async {
      final container = buildContainer(registry);
      await container.read(workspaceProvider.future);
      container.read(projectWorkspaceSyncProvider);

      final notifier = container.read(workspaceProvider.notifier);
      final tabA = await notifier.openTab(
        displayName: 'alpha',
        payload: LintcruxTabPayload(projectPath: alphaPath),
      );
      await notifier.openTab(
        displayName: 'beta',
        payload: LintcruxTabPayload(projectPath: betaPath),
      );
      final both = await _settleUntil(
        () => registry.current.openProjects.length == 2,
      );
      expect(both, isTrue);

      await notifier.closeTab(tabA);
      final closed = await _settleUntil(
        () =>
            registry.current.openProjects.length == 1 &&
            registry.current.openProjects.single.projectPath == betaPath,
      );
      expect(closed, isTrue, reason: 'closed tab should leave the registry');
    });
  });

  test(
    'open-core NoopProjectRegistry degrades to single-project recording',
    () async {
      final container = buildContainer(NoopProjectRegistry());
      await container.read(workspaceProvider.future);
      container.read(projectWorkspaceSyncProvider);

      final notifier = container.read(workspaceProvider.notifier);
      await notifier.openTab(
        displayName: 'alpha',
        payload: LintcruxTabPayload(projectPath: alphaPath),
      );
      await notifier.openTab(
        displayName: 'beta',
        payload: LintcruxTabPayload(projectPath: betaPath),
      );

      // Replace-on-open: only ever one open project, and it stabilizes on
      // the active tab without the recorder livelocking.
      final settled = await _settleUntil(
        () =>
            container
                    .read(projectRegistryProvider)
                    .current
                    .openProjects
                    .length ==
                1 &&
            container
                    .read(projectRegistryProvider)
                    .current
                    .openProjects
                    .single
                    .projectPath ==
                betaPath,
      );
      expect(
        settled,
        isTrue,
        reason: 'single-project registry should hold exactly the active tab',
      );
    },
  );

  // ───────────────────────────────────────────────────────────────────────
  // Tab dedupe (beta regression) — the registry is the *second* place a duplicate tab can
  // come from. The workspace tab holds the path exactly as it arrived; the
  // Pro registry stores `p.normalize(p.absolute(path))`, and so does the
  // double. Keyed on raw strings, this loop saw one project as two.
  // ───────────────────────────────────────────────────────────────────────
  group('ProjectWorkspaceSync path identity', () {
    late FakeMultiProjectRegistry registry;
    late String projectPath;

    setUp(() {
      projectPath = p.join(tempDir.path, 'riscv-soc.lintcrux');
      File(projectPath).writeAsStringSync('{}');
      registry = FakeMultiProjectRegistry();
    });

    test('a relative tab path records the project exactly once', () async {
      final counting = _CountingRegistry(registry);
      final container = buildContainer(counting);
      await container.read(workspaceProvider.future);
      anchorSync(container);

      // The spelling a shell hands the CLI.
      await container
          .read(workspaceProvider.notifier)
          .openTab(
            displayName: 'riscv-soc',
            payload: LintcruxTabPayload(
              projectPath: p.relative(projectPath),
            ),
          );

      final recorded = await _settleUntil(
        () => counting.current.openProjects.isNotEmpty,
      );
      expect(recorded, isTrue, reason: 'the tab was never recorded');

      // Let the loop run well past its convergence point. Keyed on raw
      // strings the two sides never agreed: the tab said
      // `riscv-soc.lintcrux`, the registry said
      // `/…/tmp/…/riscv-soc.lintcrux`, so step 3a re-recorded the "missing"
      // project on every pass until the hard pass cap gave up — burning the
      // cap on every kick, forever, and leaving the sides still disagreeing.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        counting.openProjectCalls,
        1,
        reason: 'the same project must be recorded once, not once per pass',
      );
      expect(counting.current.openProjects.length, 1);
      expect(container.read(workspaceProvider).requireValue.tabs.length, 1);
    });

    test('a `..` segment records the project exactly once', () async {
      final counting = _CountingRegistry(registry);
      final container = buildContainer(counting);
      await container.read(workspaceProvider.future);
      anchorSync(container);

      await container
          .read(workspaceProvider.notifier)
          .openTab(
            displayName: 'riscv-soc',
            payload: LintcruxTabPayload(
              projectPath: p.join(
                tempDir.path,
                'sub',
                '..',
                'riscv-soc.lintcrux',
              ),
            ),
          );

      await _settleUntil(() => counting.current.openProjects.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(counting.openProjectCalls, 1);
      // Step 2 would otherwise open a second tab under the registry's own
      // (canonical) spelling; the identity keys make the loop recognise its
      // own recording.
      expect(container.read(workspaceProvider).requireValue.tabs.length, 1);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Declined restore (beta regression) — deleting `<appSupport>/workspace.json` did not stop the
  // tabs returning, because the registry keeps its own persisted open-project
  // list and this sync re-seeds tabs from it. With the restore gate declined,
  // that side door has to stay shut too.
  // ───────────────────────────────────────────────────────────────────────
  group('ProjectWorkspaceSync honors a declined launch restore', () {
    late String projectPath;

    setUp(() {
      projectPath = p.join(tempDir.path, 'riscv-soc.lintcrux');
      File(projectPath).writeAsStringSync('{}');
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    Future<ProviderContainer> launch({
      required ProjectRegistry registry,
      required bool restore,
    }) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(RestoreTabsSettingsCodec.prefsKey, restore);
      // Mirrors `bootstrap`: the preference is resolved before the tree
      // exists and handed in as a plain value, never awaited from the
      // notifier.
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
          projectRegistryProvider.overrideWithValue(registry),
          launchRestoreDecisionProvider.overrideWithValue(decision),
        ],
      );
      containersToDispose.add(container);
      return container;
    }

    /// A registry holding one open, active project — the state a previous
    /// session's `openProject` left persisted — that has *not yet hydrated*.
    ///
    /// Un-hydrated on purpose: the Pro registry hydrates asynchronously, after
    /// the workspace has already resolved. That ordering is the whole mechanism
    /// behind the declined-restore regression — the workspace document can be
    /// deleted (or declined) and the tabs still come back, because the
    /// registry's own `<appSupport>/<product>/workspace.json` is a second copy
    /// that this sync re-seeds tabs from. `hydrate()` below stands in for the
    /// late `restore()`.
    FakeMultiProjectRegistry pendingSeededRegistry() {
      final seeded = FakeMultiProjectRegistry.describe(projectPath);
      return FakeMultiProjectRegistry(
        pending: ProjectWorkspace(
          openProjects: <ProjectDescriptor>[seeded],
          activeProjectId: seeded.id,
        ),
      );
    }

    test('restore on: the registry re-seeds its tab', () async {
      final registry = pendingSeededRegistry();
      final container = await launch(registry: registry, restore: true);
      await container.read(workspaceProvider.future);
      anchorSync(container);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // The registry hydrates late, exactly as the Pro deferred override
      // does, and publishes an active project the workspace knows nothing
      // about.
      registry.hydrate();

      final reopened = await _settleUntil(
        () => container.read(workspaceProvider).requireValue.tabs.isNotEmpty,
      );
      expect(
        reopened,
        isTrue,
        reason: 'restore-on must still honor registry-driven activation',
      );
    });

    test('restore off: no tab is re-seeded from the registry', () async {
      final registry = pendingSeededRegistry();
      final container = await launch(registry: registry, restore: false);
      await container.read(workspaceProvider.future);
      expect(
        container.read(workspaceProvider.notifier).launchRestoreDeclined,
        isTrue,
      );
      anchorSync(container);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      registry.hydrate();

      // Give the convergence loop every chance to put the tab back.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(container.read(workspaceProvider).requireValue.tabs, isEmpty);
      // And the stale registry entry is retired into recents rather than
      // left to re-seed on the next launch.
      expect(registry.current.openProjects, isEmpty);
    });

    test('restore off: a user-opened tab still records normally', () async {
      // The gate is a launch-time restriction, not a permanent one.
      final registry = pendingSeededRegistry();
      final container = await launch(registry: registry, restore: false);
      await container.read(workspaceProvider.future);
      anchorSync(container);
      registry.hydrate();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      await container
          .read(workspaceProvider.notifier)
          .openTab(
            displayName: 'riscv-soc',
            payload: LintcruxTabPayload(projectPath: projectPath),
          );

      final recorded = await _settleUntil(
        () => registry.current.openProjects.length == 1,
      );
      expect(recorded, isTrue);
      expect(container.read(workspaceProvider).requireValue.tabs.length, 1);
    });
  });
}

/// Delegating [ProjectRegistry] that counts [openProject] calls.
///
/// The raw-string-keyed sync recorded the same project once per convergence
/// pass; the registry itself is idempotent, so the churn is invisible in the
/// resulting workspace and only a call count can see it.
class _CountingRegistry implements ProjectRegistry {
  _CountingRegistry(this._delegate);

  final ProjectRegistry _delegate;

  /// How many times [openProject] has been called.
  int openProjectCalls = 0;

  @override
  Future<ProjectDescriptor> openProject(String projectPath) {
    openProjectCalls++;
    return _delegate.openProject(projectPath);
  }

  @override
  ProjectWorkspace get current => _delegate.current;

  @override
  Future<void> closeProject(String projectId, {bool hardClose = false}) =>
      _delegate.closeProject(projectId, hardClose: hardClose);

  @override
  Future<void> closeAllProjects() => _delegate.closeAllProjects();

  @override
  Future<void> setActiveProject(String projectId) =>
      _delegate.setActiveProject(projectId);

  @override
  Future<void> pinProject(String projectId, {required bool pinned}) =>
      _delegate.pinProject(projectId, pinned: pinned);

  @override
  Future<void> reorderProjects(List<String> newOrderIds) =>
      _delegate.reorderProjects(newOrderIds);

  @override
  Future<void> clearRecentProject(String projectId) =>
      _delegate.clearRecentProject(projectId);

  @override
  Future<void> shutdownAll() => _delegate.shutdownAll();

  @override
  Stream<ProjectWorkspace> watch() => _delegate.watch();
}
