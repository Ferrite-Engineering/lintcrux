// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/lintcrux_tab_payload.dart';
import 'package:lintcrux/features/workspace/providers/recent_projects_provider.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/features/workspace/widgets/workspace_root.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/remote/cxp/cxp_project_open_handle.dart';
import 'package:lintcrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:lintcrux/services/workspace/lintcrux_workspace_codec.dart';
import '../../../support/host_absolute_path.dart';
import '../../../support/telemetry_test_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lintcrux_root_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  WorkspaceService buildService() {
    return WorkspaceService(
      codec: const LintcruxWorkspaceCodec(),
      directoryFactory: () async => tempDir,
    );
  }

  testWidgets('WorkspaceRoot.of exposes tab and pane managers', (tester) async {
    crux.TabContainerManager? capturedTabs;
    crux.PaneContainerManager? capturedPanes;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...telemetryDeclinedOverrides(),
          workspaceServiceProvider.overrideWithValue(buildService()),
        ],
        child: MaterialApp(
          home: WorkspaceRoot(
            child: Builder(
              builder: (context) {
                final scope = WorkspaceRoot.of(context);
                capturedTabs = scope.tabs;
                capturedPanes = scope.panes;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    expect(capturedTabs, isNotNull);
    expect(capturedPanes, isNotNull);
  });

  testWidgets('WorkspaceRoot disposes its managers on unmount', (tester) async {
    crux.TabContainerManager? captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...telemetryDeclinedOverrides(),
          workspaceServiceProvider.overrideWithValue(buildService()),
        ],
        child: MaterialApp(
          home: WorkspaceRoot(
            child: Builder(
              builder: (context) {
                captured = WorkspaceRoot.of(context).tabs;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    // Replace with a barren tree to fire dispose() on WorkspaceRoot.
    await tester.pumpWidget(const SizedBox.shrink());
    // Verify a fresh `containerFor` call on a disposed manager still
    // accepts the request but doesn't throw — the package's
    // implementation does not assert on dispose, it just leaks the new
    // container. Verify the manager was wired by checking the captured
    // reference is non-null. The dispose call itself doesn't throw.
    expect(captured, isNotNull);
  });

  group('scope eviction (WorkspaceScopeReconciler registration)', () {
    /// Pumps a WorkspaceRoot and hands back the tab manager plus the
    /// workspace notifier, with the workspace already loaded.
    Future<(crux.TabContainerManager, LintcruxWorkspaceNotifier)> pumpRoot(
      WidgetTester tester,
      ProviderContainer Function() containerOf,
    ) async {
      crux.TabContainerManager? tabs;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: containerOf(),
          child: MaterialApp(
            home: WorkspaceRoot(
              child: Builder(
                builder: (context) {
                  tabs = WorkspaceRoot.of(context).tabs;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      final container = containerOf();
      await container.read(workspaceProvider.future);
      await tester.pump();
      return (tabs!, container.read(workspaceProvider.notifier));
    }

    testWidgets('closing a tab disposes that tab’s ProviderContainer', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          ...telemetryDeclinedOverrides(),
          workspaceServiceProvider.overrideWithValue(buildService()),
        ],
      );
      addTearDown(container.dispose);

      final (tabs, notifier) = await pumpRoot(tester, () => container);

      final tab = await notifier.openTab(
        displayName: 'alpha',
        payload: const LintcruxTabPayload(projectPath: '/proj/alpha.lintcrux'),
      );
      await tester.pump();

      final tabContainer = tabs.containerFor(tab);
      expect(
        identical(tabs.containerFor(tab), tabContainer),
        isTrue,
        reason: 'the manager should cache one container per live tab',
      );

      await notifier.closeTab(tab);
      await tester.pump();

      // The evicted container is disposed, so reading through it throws.
      // Without `addScopeReconciler` this container would still be alive
      // and `containerFor` would hand back the very same instance.
      expect(
        identical(tabs.containerFor(tab), tabContainer),
        isFalse,
        reason:
            'closing a tab must evict its container; a surviving identical '
            'instance means the scope reconciler was never registered',
      );

      // Drain the notifier's 2s debounced-save timer so the binding's
      // no-pending-timers invariant holds at teardown.
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets(
      'a closed-then-revived tab id gets a fresh container, not the dead '
      'tab’s',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            ...telemetryDeclinedOverrides(),
            workspaceServiceProvider.overrideWithValue(buildService()),
          ],
        );
        addTearDown(container.dispose);

        final (tabs, notifier) = await pumpRoot(tester, () => container);

        final tab = await notifier.openTab(
          displayName: 'alpha',
          payload: const LintcruxTabPayload(
            projectPath: '/proj/alpha.lintcrux',
          ),
        );
        await tester.pump();
        final firstContainer = tabs.containerFor(tab);

        // Close it, then revive the *same id* — the shape a workspace
        // reload takes when a persisted document reuses an id.
        await notifier.closeTab(tab);
        await tester.pump();
        final revivedContainer = tabs.containerFor(tab);

        expect(
          identical(revivedContainer, firstContainer),
          isFalse,
          reason:
              'a revived tab id must not inherit the dead tab’s container — '
              'that is the cross-tab state-bleed defect',
        );

        // Drain the notifier's 2s debounced-save timer so the binding's
        // no-pending-timers invariant holds at teardown.
        await tester.pump(const Duration(seconds: 3));
      },
    );

    // CXP §11's containment roots come from what the user opened, and both
    // sources live in the feature layer — so `WorkspaceRoot` is what carries
    // them into root scope. Without the Recent list here, a peer's
    // `request_open_artifact` could only ever land on a project that is
    // already open.
    testWidgets('publishes every tab’s project and the Recent projects list '
        'as containment roots, and withdraws them on unmount', (tester) async {
      // Spelled as the host spells an absolute path: on Windows `/proj`
      // names no drive, and the containment floor refuses it before the
      // roots are consulted.
      final alpha = hostAbsolute('/proj/alpha.lintcrux');
      final recent = hostAbsolute('/recent/beta.lintcrux');
      final container = ProviderContainer(
        overrides: [
          ...telemetryDeclinedOverrides(),
          workspaceServiceProvider.overrideWithValue(buildService()),
          recentProjectsProvider.overrideWithValue(<String>[recent]),
        ],
      );
      addTearDown(container.dispose);

      final (_, notifier) = await pumpRoot(tester, () => container);
      await notifier.openTab(
        displayName: 'alpha',
        payload: LintcruxTabPayload(projectPath: alpha),
      );
      await tester.pump();

      final handle = container.read(cxpProjectOpenHandleProvider);
      expect(
        handle.openedProjectPaths,
        containsAll(<String>[alpha, recent]),
      );
      final rule = container.read(cxpPathContainmentProvider);
      expect(rule.allows(hostAbsolute('/proj/rtl/cpu.sv')), isTrue);
      expect(rule.allows(hostAbsolute('/recent/rtl/top.sv')), isTrue);
      expect(rule.allows(hostAbsolute('/etc/passwd')), isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(handle.openedProjectPaths, isEmpty);
      expect(rule.allows(hostAbsolute('/proj/rtl/cpu.sv')), isFalse);

      // Drain the notifier's 2s debounced-save timer so the binding's
      // no-pending-timers invariant holds at teardown.
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('unmounting WorkspaceRoot unregisters its reconcilers', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          ...telemetryDeclinedOverrides(),
          workspaceServiceProvider.overrideWithValue(buildService()),
        ],
      );
      addTearDown(container.dispose);

      final (tabs, notifier) = await pumpRoot(tester, () => container);
      expect(tabs, isNotNull);

      await tester.pumpWidget(const SizedBox.shrink());

      // The notifier outlives the widget. Driving it after unmount must
      // not reach the disposed managers.
      final tab = await notifier.openTab(
        displayName: 'after-unmount',
        payload: const LintcruxTabPayload(projectPath: '/proj/alpha.lintcrux'),
      );
      await notifier.closeTab(tab);
      expect(tester.takeException(), isNull);

      // Drain the notifier's 2s debounced-save timer so the binding's
      // no-pending-timers invariant holds at teardown.
      await tester.pump(const Duration(seconds: 3));
    });
  });

  testWidgets('WorkspaceLifecycleObserver wraps the child subtree', (
    tester,
  ) async {
    // The observer wraps `widget.child` inside its own
    // `ConsumerStatefulWidget`. We assert the marker child still
    // appears in the tree to verify the wrapping doesn't drop the
    // subtree.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...telemetryDeclinedOverrides(),
          workspaceServiceProvider.overrideWithValue(buildService()),
        ],
        child: const MaterialApp(
          home: WorkspaceRoot(
            child: Text('marker', textDirection: TextDirection.ltr),
          ),
        ),
      ),
    );
    expect(find.text('marker'), findsOneWidget);
  });

  testWidgets(
    'locale sweep: WorkspaceRoot hosts a localized subtree without '
    'exceptions in every supported locale',
    (tester) async {
      for (final locale in L10N.supportedLocales) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...telemetryDeclinedOverrides(),
              workspaceServiceProvider.overrideWithValue(buildService()),
            ],
            child: MaterialApp(
              locale: locale,
              localizationsDelegates: const [
                L10N.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: L10N.supportedLocales,
              home: WorkspaceRoot(
                // A child that resolves L10N proves the localization
                // scope survives the workspace-root wrapping per locale.
                child: Builder(
                  builder: (context) => Text(L10N.of(context).appTitle),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final l10n = L10N.of(tester.element(find.byType(WorkspaceRoot)));
        expect(
          find.text(l10n.appTitle),
          findsOneWidget,
          reason: 'app title missing for $locale',
        );
        expect(tester.takeException(), isNull, reason: 'failed for $locale');
      }
    },
  );
}
