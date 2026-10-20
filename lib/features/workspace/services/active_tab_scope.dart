// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/features/workspace/widgets/workspace_root.dart';

/// Where a dialog that reads the active tab's providers is shown.
///
/// `showDialog` mounts a dialog on the root navigator, outside every tab's
/// `UncontrolledProviderScope`, so a dialog that reads `currentProjectProvider`,
/// `lintRunProvider`, `violationStoreProvider`, ... from there sees the root
/// container, where no project is loaded. LintCrux used to fix that by
/// wrapping the dialog in a second scope over the tab's container, which let
/// Riverpod flush that container's rebuilds from two scopes in one frame and
/// mark the tab's own widgets dirty in the middle of a build.
///
/// Each tab's content is instead built on its own nested navigator
/// (`PaneHost.tabNavigators`, owned by [WorkspaceRoot]), and a dialog that
/// needs the tab is pushed on it:
///
/// ```dart
/// showCruxDialog<void>(
///   context: context,
///   navigator: ActiveTab.navigatorFor(context),
///   builder: (_) => const MyDialog(),
/// );
/// ```
///
/// The dialog is then built under the tab's one scope. It covers the tab's
/// area, not the window, and belongs to the tab: switching tabs hides it with
/// its tab, and closing the tab closes it (its future completes with null).
abstract final class ActiveTab {
  /// The navigator of the tab [callerContext] is inside, else the active
  /// tab's navigator, else null.
  ///
  /// Null when no tab is active (the empty workspace) or there is no
  /// [WorkspaceRoot] above [callerContext]; `showCruxDialog` then uses the
  /// root navigator, as before, and the dialog sees the root container.
  ///
  /// [callerContext] may be inside a tab (a panel, or a dialog already on the
  /// tab's navigator, so a dialog opened from a dialog lands on the same tab)
  /// or outside every tab (the menu bar, the palette, the routerDelegate's
  /// navigator context).
  static NavigatorState? navigatorFor(BuildContext callerContext) =>
      _resolve(callerContext)?.navigator;

  /// [surface]'s `ModalGuard` key for the tab [navigatorFor] resolves, or
  /// [surface] itself when there is none.
  ///
  /// A dialog that belongs to a tab stays open, hidden, while another tab is
  /// active. One process-wide key would then swallow the same command in the
  /// other tab with nothing on screen to explain it, so each tab guards its
  /// own copy.
  static String guardKey(BuildContext callerContext, String surface) {
    final tab = _resolve(callerContext)?.tab;
    return tab == null ? surface : '$surface@${tab.value}';
  }

  static ({crux.TabId tab, NavigatorState navigator})? _resolve(
    BuildContext callerContext,
  ) {
    final inTab = crux.cruxTabNavigatorOf(callerContext);
    if (inTab != null) {
      final container = ProviderScope.containerOf(callerContext, listen: false);
      return (tab: container.read(crux.tabIdProvider), navigator: inTab);
    }
    final scope = callerContext
        .getInheritedWidgetOfExactType<WorkspaceRootScope>();
    final navigators = scope?.tabNavigators;
    if (navigators == null) return null;
    final root = ProviderScope.containerOf(callerContext, listen: false);
    final active = root.read(workspaceProvider).value?.activeTabId;
    if (active == null) return null;
    final navigator = navigators.navigatorFor(active);
    if (navigator == null) return null;
    return (tab: active, navigator: navigator);
  }
}

/// Resolves the ACTIVE tab's per-tab `ProviderContainer` from
/// [callerContext], or `null` when no workspace is hydrated or no tab
/// is active.
///
/// For an action handler that needs to `read` / mutate the active tab's
/// providers directly (a Pro action opener setting a baseline, toggling a
/// bookmark, force-running without cache) rather than mounting a widget.
/// Reading these providers from the root container instead silently
/// resolves the empty root-scope instances. A widget that needs the tab
/// is shown on [ActiveTab.navigatorFor] instead; never wrap one in a
/// second `UncontrolledProviderScope` over this container.
///
/// [callerContext] must have [WorkspaceRoot] in its ancestor chain
/// (the routerDelegate's navigator context qualifies, and so does any
/// context inside a tab or a dialog on a tab's navigator). Callers should
/// fall back to `ProviderScope.containerOf(callerContext)` when this
/// returns `null` (empty workspace).
ProviderContainer? activeTabContainerOf(BuildContext callerContext) {
  final rootContainer = ProviderScope.containerOf(callerContext, listen: false);
  final workspaceAsync = rootContainer.read(workspaceProvider);
  final workspace = workspaceAsync.value;
  final activeTabId = workspace?.activeTabId;
  if (workspace == null || activeTabId == null) return null;
  final scope = WorkspaceRoot.of(callerContext);
  return scope.tabs.containerFor(activeTabId);
}
