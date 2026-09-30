// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/features/workspace/widgets/workspace_root.dart';

/// Wraps [child] in an [UncontrolledProviderScope] bound to the
/// active tab's per-tab `ProviderContainer`, so widgets mounted via
/// `showDialog` / `Navigator.push` see the same `currentProjectProvider`,
/// `lintRunProvider`, `violationStoreProvider`, … as the rest of the
/// active tab's IDE shell.
///
/// `showDialog` (and `Navigator.push`) defaults the dialog's
/// `ProviderScope` to the route's parent — which is the root container
/// when the call site is the routerDelegate's navigator. Without this
/// wrapper, a Pro screen opened from the command palette or menu bar
/// reads `currentProjectProvider == null` from the root scope and
/// renders its "No project open" empty state even when a tab is
/// active. Pro openers (Baseline / Bookmark / Filter Preset Manager /
/// Waiver Review) call this from their `showAsDialog` static methods.
///
/// Returns [child] unchanged when no workspace is yet hydrated or no
/// tab is active — callers don't need to special-case the empty
/// workspace.
///
/// [callerContext] must be a context with [WorkspaceRoot] in its
/// ancestor chain (the activating context — typically the
/// routerDelegate's navigator state context). The dialog builder's own
/// context cannot be used here because the dialog is pushed onto the
/// root Navigator and so does not have [WorkspaceRoot] above it.
Widget wrapInActiveTabScope(BuildContext callerContext, Widget child) {
  final container = activeTabContainerOf(callerContext);
  if (container == null) return child;
  return UncontrolledProviderScope(
    container: container,
    child: child,
  );
}

/// Resolves the ACTIVE tab's per-tab `ProviderContainer` from
/// [callerContext], or `null` when no workspace is hydrated or no tab
/// is active.
///
/// The imperative sibling of [wrapInActiveTabScope]: use it when an
/// action handler needs to `read` / mutate the active tab's providers
/// directly (a Pro action opener setting a baseline, toggling a
/// bookmark, force-running without cache) rather than mounting a
/// widget. Reading these providers from the root container instead
/// silently resolves the empty root-scope instances — the scope-leak
/// class this helper exists to prevent.
///
/// [callerContext] must have [WorkspaceRoot] in its ancestor chain
/// (the routerDelegate's navigator context qualifies). Callers should
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
