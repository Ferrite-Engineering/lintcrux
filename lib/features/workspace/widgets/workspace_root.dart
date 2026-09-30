// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:lintcrux/features/project/services/open_project_service.dart';
import 'package:lintcrux/features/workspace/providers/recent_projects_provider.dart';
import 'package:lintcrux/features/workspace/providers/tab_overrides_factory.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/features/workspace/services/open_project_in_workspace.dart';
import 'package:lintcrux/services/engines/yosys/yosys_process_reaper.dart';
import 'package:lintcrux/services/remote/cxp/cxp_project_open_handle.dart';
import 'package:lintcrux/services/workspace/active_tab_container_handle.dart';
import 'package:lintcrux/services/workspace/tab_container_manager_holder.dart';

/// Holds the lifetime of the per-tab and per-pane
/// [crux.ProviderContainer] managers and exposes them down the widget
/// tree.
///
/// One [WorkspaceRoot] sits at the top of the routed subtree, just
/// inside the [ProviderScope]. It:
///
/// * Resolves the root [ProviderContainer] at `initState` via
///   [ProviderScope.containerOf] (`listen: false`).
/// * Creates a [crux.TabContainerManager] with the LintCrux-specific
///   [lintcruxTabOverridesFactory], and a [crux.PaneContainerManager]
///   with an empty per-pane override factory (LintCrux has no
///   per-pane providers).
/// * Registers both managers as [crux.WorkspaceScopeReconciler]s on the
///   workspace notifier, so closing a tab or pane disposes its
///   `ProviderContainer` instead of leaking it for the process lifetime,
///   and a revived tab id never inherits a dead tab's container.
///   Unregisters them again in [dispose].
/// * Disposes both managers in [dispose] so a hot-restart cleans up
///   live containers.
/// * Wraps the [child] in a [crux.WorkspaceLifecycleObserver] that
///   flushes the pending workspace save on
///   `AppLifecycleState.paused` / `detached`.
/// * Wraps the [child] in a [YosysProcessReaper] that kills spawned
///   `yosys` processes on `detached`, so a hard quit cannot orphan one.
/// * Exposes the managers to descendants via [WorkspaceRoot.of] so
///   `ViewerScaffold` can hand them to [crux.PaneHost].
class WorkspaceRoot extends ConsumerStatefulWidget {
  /// Creates a [WorkspaceRoot].
  const WorkspaceRoot({required this.child, super.key});

  /// The routed subtree (typically the [MaterialApp.router] body).
  final Widget child;

  /// Looks up the closest [WorkspaceRoot] ancestor's managers via the
  /// surrounding [WorkspaceRootScope] `InheritedWidget`. Use this from
  /// descendants of [WorkspaceRoot] (the common case — UI widgets
  /// reach `WorkspaceRoot.of(context)` to get the managers).
  ///
  /// Throws when called outside a [WorkspaceRoot]; this is a
  /// developer error.
  static WorkspaceRootScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<WorkspaceRootScope>();
    assert(
      scope != null,
      'WorkspaceRoot.of() called with a context that has no '
      'WorkspaceRoot ancestor.',
    );
    return scope!;
  }

  @override
  ConsumerState<WorkspaceRoot> createState() => _WorkspaceRootState();
}

/// Public state interface for [WorkspaceRoot] so the app-bootstrap
/// (which holds a `GlobalKey<WorkspaceRootState>`) can resolve the
/// container managers without walking the tree.
///
/// Descendants prefer [WorkspaceRoot.of] over this surface.
abstract class WorkspaceRootState extends ConsumerState<WorkspaceRoot> {
  /// Per-tab `ProviderContainer` manager.
  crux.TabContainerManager get tabs;

  /// Per-pane `ProviderContainer` manager.
  crux.PaneContainerManager get panes;
}

class _WorkspaceRootState extends WorkspaceRootState {
  late final crux.TabContainerManager _tabs;
  late final crux.PaneContainerManager _panes;

  /// The notifier this state registered its scope reconcilers with;
  /// retained so [dispose] can unregister them. The notifier outlives
  /// this widget (it is root-scoped), so leaving stale reconcilers
  /// attached would keep disposed managers reachable.
  LintcruxWorkspaceNotifier? _workspaceNotifier;

  /// The services-layer handle this state published its active-tab
  /// resolver into; retained so [dispose] can clear it without touching
  /// the (possibly defunct) `BuildContext`.
  ActiveTabContainerHandle? _activeTabHandle;

  /// The services-layer handle this state published its project opener into;
  /// retained so [dispose] can clear it without touching
  /// `ref` during disposal.
  CxpProjectOpenHandle? _projectOpenHandle;

  /// The root-scope holder this state published its [crux.TabContainerManager]
  /// into, so the action-flags mirror can reach the active tab's container.
  /// Retained so [dispose] can clear it.
  TabContainerManagerHolder? _tabManagerHolder;

  @override
  crux.TabContainerManager get tabs => _tabs;

  @override
  crux.PaneContainerManager get panes => _panes;

  @override
  void initState() {
    super.initState();
    final root = ProviderScope.containerOf(context, listen: false);
    // The Pro overlay contributes per-tab overrides through
    // `extraTabOverridesProvider` (open-core default: empty). Spread AFTER
    // the open-core factory list so later overrides win, matching the
    // root-container conflict semantics. This is the seam that lets the
    // Pro trend dispatcher (and any future per-tab Pro service) resolve
    // the active tab's own state instead of the empty root container.
    final extraTabOverrides = root.read(extraTabOverridesProvider);
    _tabs = crux.TabContainerManager(
      rootContainer: root,
      overridesFactory: (tabId) => <Override>[
        ...lintcruxTabOverridesFactory(tabId),
        ...extraTabOverrides,
      ],
    );
    _panes = crux.PaneContainerManager(rootContainer: root);

    // Register both managers for the structural scope-eviction signal.
    // `WorkspaceNotifier` emits the surviving tab/pane id set after every
    // state transition; each manager disposes the containers whose scope
    // is gone.
    //
    // Skipping this compiles and runs, which is precisely why it is easy
    // to lose: without it every closed tab's `ProviderContainer` stays
    // alive for the process lifetime (leaking its providers, stream
    // subscriptions and timers), and a workspace reload that revives a
    // previously-used tab id is handed the *dead* tab's container —
    // bleeding one tab's lint results and filters into another. This is
    // the same per-tab scope-leak class that project scope guards against;
    // container eviction is that defect one layer down.
    //
    // Registered here rather than at notifier construction because the
    // managers need the root `ProviderContainer`, which does not exist
    // until this State is mounted.
    final workspaceNotifier = root.read(workspaceProvider.notifier)
      ..addScopeReconciler(_tabs)
      ..addScopeReconciler(_panes);
    _workspaceNotifier = workspaceNotifier;

    // Publish the active-tab container resolver into the services-layer
    // handle so root-scoped services with no BuildContext (the CXP
    // inbound path) can act on the active tab's per-tab state. A legal
    // features → services write, mirroring `CxpServerHandle`.
    ProviderContainer? resolveActiveTab() {
      final workspace = root.read(workspaceProvider).value;
      final activeTabId = workspace?.activeTabId;
      if (activeTabId == null) return null;
      return _tabs.containerFor(activeTabId);
    }

    final handle = root.read(activeTabContainerHandleProvider);
    _activeTabHandle = handle;
    handle.resolver = resolveActiveTab;

    // Publish the manager itself too. The resolver above is imperative —
    // fine for the CXP inbound path, which acts once on demand — but the
    // active-tab action-flags mirror is a root *provider* that has to
    // subscribe to the active tab's state and re-emit it, so it needs the
    // manager to resolve containers as the active tab changes.
    _tabManagerHolder = root.read(tabContainerManagerHolderProvider);
    _tabManagerHolder!.manager = _tabs;

    // Publish the project opener into the services-layer handle so the
    // root-hosted CXP inbound path can open a design a peer named. Uses this
    // WorkspaceRoot's tab-container factory, which the root-scoped opener
    // otherwise cannot reach. Cleared on dispose.
    //
    // And the projects the user has opened, which CXP §11's containment rule
    // reads before anything a peer named may be opened: every tab's project
    // plus the Recent projects list. Read live on each check, so a project
    // opened after the server came up is inside the rule at once.
    final openHandle = root.read(cxpProjectOpenHandleProvider)
      ..opener = (path) async {
        final opener = root.read(openProjectInWorkspaceProvider)(
          _tabs.containerFor,
        );
        final result = await opener.openProject(path);
        return result is OpenProjectSuccess;
      }
      ..projectPaths = () => <String>[
        for (final tab
            in root.read(workspaceProvider).value?.tabs ??
                const <WorkspaceTab>[])
          tab.payload.projectPath,
        ...root.read(recentProjectsProvider),
      ];
    _projectOpenHandle = openHandle;
  }

  @override
  void dispose() {
    _projectOpenHandle?.opener = null;
    _projectOpenHandle?.projectPaths = null;
    _projectOpenHandle = null;
    _activeTabHandle?.resolver = null;
    _activeTabHandle = null;
    _tabManagerHolder?.manager = null;
    _tabManagerHolder = null;
    _workspaceNotifier
      ?..removeScopeReconciler(_tabs)
      ..removeScopeReconciler(_panes);
    _workspaceNotifier = null;
    _tabs.dispose();
    _panes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WorkspaceRootScope(
      tabs: _tabs,
      panes: _panes,
      child: crux.WorkspaceLifecycleObserver(
        provider: workspaceProvider,
        // Reaps Yosys child processes on `detached` so a hard quit does
        // not orphan a `yosys` burning a core. Deliberately not one of
        // the observer's `additionalFlushes` — those also fire on
        // `paused`, where a background lint run must keep going.
        child: YosysProcessReaper(child: widget.child),
      ),
    );
  }
}

/// Inherited widget making the per-tab and per-pane container managers
/// available to descendants. Internal to [WorkspaceRoot] — consumers
/// reach it via [WorkspaceRoot.of]. Public only because [WorkspaceRoot.of]
/// returns this type.
class WorkspaceRootScope extends InheritedWidget {
  /// Creates a [WorkspaceRootScope].
  const WorkspaceRootScope({
    required this.tabs,
    required this.panes,
    required super.child,
    super.key,
  });

  /// Per-tab `ProviderContainer` manager.
  final crux.TabContainerManager tabs;

  /// Per-pane `ProviderContainer` manager.
  final crux.PaneContainerManager panes;

  @override
  bool updateShouldNotify(WorkspaceRootScope oldWidget) =>
      tabs != oldWidget.tabs || panes != oldWidget.panes;
}
