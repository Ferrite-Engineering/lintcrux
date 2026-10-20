// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/lintcrux_tab_payload.dart';
import 'package:lintcrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:lintcrux/features/diagnostics/widgets/app_diagnostics_dialog.dart';
import 'package:lintcrux/features/diagnostics/widgets/tab_diagnostics_drawer.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/features/workspace/services/active_tab_scope.dart';
import 'package:lintcrux/features/workspace/widgets/workspace_root.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/workspace/lintcrux_workspace_codec.dart';

import '../../../support/telemetry_test_store.dart';

// A dialog on the root navigator is outside every tab's
// `UncontrolledProviderScope`, and LintCrux used to give one that reads a
// tab's providers a SECOND scope over the tab's container. Riverpod flushes a
// container's pending rebuilds from inside the build of every scope that
// mounts it; the dialog's scope builds first and flushes into the tab
// content, which it is not an ancestor of, so a per-tab write while the
// dialog was open marked the tab's widgets dirty mid-build ("setState() or
// markNeedsBuild() called during build"). The dialogs are now pushed on the
// tab's own navigator, under the one scope the pane host mounts.

const _alpha = LintcruxTabPayload(projectPath: '/w/alpha.lintcrux');
const _beta = LintcruxTabPayload(projectPath: '/w/beta.lintcrux');

/// Serves a fixed two-tab document and saves nowhere, so the real
/// [LintcruxWorkspaceNotifier] runs without disk I/O.
class _MemoryWorkspaceService extends WorkspaceService {
  _MemoryWorkspaceService(this._seed)
    : super(codec: const LintcruxWorkspaceCodec());

  final Workspace _seed;

  @override
  Future<Workspace> load() async => _seed;

  @override
  Future<void> save(Workspace workspace) async {}
}

Workspace _twoTabs() {
  final pane = crux.PaneId.generate();
  final a = crux.TabId.generate();
  final b = crux.TabId.generate();
  return Workspace(
    tabs: [
      WorkspaceTab(id: a, displayName: 'alpha', paneId: pane, payload: _alpha),
      WorkspaceTab(id: b, displayName: 'beta', paneId: pane, payload: _beta),
    ],
    panes: [crux.WorkspacePane(id: pane, activeTabId: a)],
    activePaneId: pane,
  );
}

/// The tab content: a per-tab DERIVED provider, watched (the violation
/// table in the field report watched one too: a derived provider's rebuild
/// is the one Riverpod defers to a scope's build), and a button that opens
/// the real App Diagnostics dialog the way the menu does.
class _TabBody extends ConsumerWidget {
  const _TabBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(tabDiagnosticsReportProvider);
    return Column(
      children: [
        Text('tab shows ${report?.projectPath ?? 'nothing'}'),
        ElevatedButton(
          onPressed: () => unawaited(AppDiagnosticsDialog.show(context)),
          child: const Text('open diagnostics'),
        ),
        ElevatedButton(
          onPressed: () => unawaited(TabDiagnosticsDrawer.open(context)),
          child: const Text('open drawer'),
        ),
      ],
    );
  }
}

void main() {
  late Workspace seed;

  setUp(() => seed = _twoTabs());

  /// [WorkspaceRoot] and a pane host built the way `ViewerScaffold` builds
  /// its own: every tab on its own navigator.
  Future<ProviderContainer> pumpWorkspace(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...telemetryDeclinedOverrides(),
          workspaceServiceProvider.overrideWithValue(
            _MemoryWorkspaceService(seed),
          ),
          engineRegistryProvider.overrideWithValue(EngineRegistry(const [])),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            L10N.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: L10N.supportedLocales,
          home: WorkspaceRoot(
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  final scope = WorkspaceRoot.of(context);
                  return crux.PaneHost<LintcruxTabPayload>(
                    provider: workspaceProvider,
                    tabs: scope.tabs,
                    panes: scope.panes,
                    tabNavigators: scope.tabNavigators,
                    emptyCanvasContent: const Text('no tabs'),
                    tabContentBuilder: (_, _) => const _TabBody(),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(WorkspaceRoot)),
      listen: false,
    );
  }

  ProviderContainer tabContainer(WidgetTester tester, crux.TabId tab) =>
      WorkspaceRoot.of(
        tester.element(find.byType(crux.PaneHost<LintcruxTabPayload>)),
      ).tabs.containerFor(tab);

  Finder dialog() => find.byType(AppDiagnosticsDialog);

  // Mutation-verified: putting `AppDiagnosticsDialog.show` back on the root
  // navigator with an `UncontrolledProviderScope(container: <the tab's>)`
  // around the dialog fails this test on the first write with the field
  // report's assertion ("setState() or markNeedsBuild() called during
  // build", on `_TabBody`, while `UncontrolledProviderScope` was building).
  testWidgets('a per-tab write while a dialog reads the same tab rebuilds '
      'the dialog and the tab content without marking either dirty '
      'mid-build', (tester) async {
    await pumpWorkspace(tester);
    final alpha = tabContainer(tester, seed.tabs.first.id);

    await tester.tap(find.text('open diagnostics'));
    await tester.pumpAndSettle();
    expect(dialog(), findsOneWidget);
    // On the tab's own navigator, so under the tab's one scope.
    expect(
      ProviderScope.containerOf(tester.element(dialog()), listen: false),
      same(alpha),
    );

    for (final name in ['first', 'second', 'third']) {
      alpha
          .read(currentProjectProvider.notifier)
          .load(LintProject(name: name, rootPath: '/w/$name'));
      // No duration: the frame builds before the zero-delay timers Riverpod
      // also arms, so the pending rebuild is flushed from inside a scope's
      // build, which is the path the assertion fired on.
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('tab shows /w/$name'), findsOneWidget);
    }
    expect(dialog(), findsOneWidget);
  });

  testWidgets('closing a tab with its dialog open closes the dialog, '
      'completes its future and frees its guard', (tester) async {
    final root = await pumpWorkspace(tester);
    final alphaId = seed.tabs.first.id;
    final context = tester.element(find.text('open diagnostics'));
    final key = ActiveTab.guardKey(context, 'appDiagnostics');
    expect(key, 'appDiagnostics@${alphaId.value}');

    var completed = false;
    unawaited(
      AppDiagnosticsDialog.show(context).then((_) => completed = true),
    );
    await tester.pumpAndSettle();
    expect(dialog(), findsOneWidget);
    expect(ModalGuard.isOpen(key), isTrue);

    await root.read(workspaceProvider.notifier).closeTab(alphaId);
    await tester.pumpAndSettle();

    expect(dialog(), findsNothing);
    expect(completed, isTrue);
    expect(ModalGuard.isOpen(key), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a dialog stays with its tab: hidden while another tab is '
      'active, which can open its own, and back on return', (tester) async {
    final root = await pumpWorkspace(tester);
    final notifier = root.read(workspaceProvider.notifier);
    final alphaId = seed.tabs.first.id;
    final betaId = seed.tabs.last.id;

    await tester.tap(find.text('open diagnostics'));
    await tester.pumpAndSettle();
    expect(dialog(), findsOneWidget);

    await notifier.setActiveTab(betaId);
    await tester.pumpAndSettle();
    // Alpha's dialog is offstage with its tab; beta opens its own.
    expect(dialog().hitTestable(), findsNothing);
    await tester.tap(find.text('open diagnostics').hitTestable());
    await tester.pumpAndSettle();
    final shown = dialog().hitTestable();
    expect(shown, findsOneWidget);
    expect(
      ProviderScope.containerOf(tester.element(shown), listen: false),
      same(tabContainer(tester, betaId)),
    );

    await notifier.setActiveTab(alphaId);
    await tester.pumpAndSettle();
    final back = dialog().hitTestable();
    expect(back, findsOneWidget);
    expect(
      ProviderScope.containerOf(tester.element(back), listen: false),
      same(tabContainer(tester, alphaId)),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the diagnostics drawer reads the active tab under its one '
      'scope, survives per-tab writes, follows a tab switch and closes '
      'with the last tab', (tester) async {
    final root = await pumpWorkspace(tester);
    final notifier = root.read(workspaceProvider.notifier);
    final alphaId = seed.tabs.first.id;
    final betaId = seed.tabs.last.id;
    final alpha = tabContainer(tester, alphaId);
    alpha
        .read(currentProjectProvider.notifier)
        .load(const LintProject(name: 'a', rootPath: '/w/a'));
    await tester.pump();

    await tester.tap(find.text('open drawer'));
    await tester.pumpAndSettle();
    final drawer = find.byType(TabDiagnosticsDrawer);
    expect(drawer, findsOneWidget);
    expect(
      ProviderScope.containerOf(tester.element(drawer), listen: false),
      same(alpha),
    );
    expect(ModalGuard.isOpen('tabDiagnostics'), isTrue);

    for (final name in ['first', 'second']) {
      alpha
          .read(currentProjectProvider.notifier)
          .load(LintProject(name: name, rootPath: '/w/$name'));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    await notifier.setActiveTab(betaId);
    await tester.pumpAndSettle();
    final moved = find.byType(TabDiagnosticsDrawer).hitTestable();
    expect(moved, findsOneWidget);
    expect(
      ProviderScope.containerOf(tester.element(moved), listen: false),
      same(tabContainer(tester, betaId)),
    );

    await notifier.closeTab(betaId);
    await tester.pumpAndSettle();
    expect(
      ProviderScope.containerOf(
        tester.element(find.byType(TabDiagnosticsDrawer)),
        listen: false,
      ),
      same(alpha),
    );
    await notifier.closeTab(alphaId);
    await tester.pumpAndSettle();
    expect(find.byType(TabDiagnosticsDrawer), findsNothing);
    expect(ModalGuard.isOpen('tabDiagnostics'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with no tab the dialog goes on the root navigator and the '
      'guard key is the plain one', (tester) async {
    seed = Workspace.empty();
    await pumpWorkspace(tester);
    final context = tester.element(find.text('no tabs'));
    expect(ActiveTab.navigatorFor(context), isNull);
    expect(ActiveTab.guardKey(context, 'appDiagnostics'), 'appDiagnostics');
  });
}
