// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mutable root-scope handle on the app's singleton [TabContainerManager].
///
/// LintCrux builds its managers inside `WorkspaceRoot.initState`, because they
/// need the **root** `ProviderContainer` as their parent and descendants reach
/// them through `WorkspaceRoot.of`. That widget-tree route is unavailable to
/// root-scope *providers*, and the active-tab action-flags mirror feeding
/// `lintcruxActionContextProvider` is exactly that: a root provider that has
/// to read the active tab's container so the menu bar, palette, toolbar, and
/// keyboard all gate on identical state.
///
/// `WorkspaceRoot` therefore publishes its manager here on mount and clears it
/// on dispose — the same seam shape as [ActiveTabContainerHandle], and a
/// mirror of NetCrux's holder of the same name.
///
/// [manager] is null before `WorkspaceRoot` mounts and in tests that never
/// mount it; consumers must treat that as "no tab available".
class TabContainerManagerHolder {
  /// The app's per-tab container manager, or null when no `WorkspaceRoot` is
  /// mounted.
  TabContainerManager? manager;
}

/// Root-scope access to the [TabContainerManagerHolder].
final tabContainerManagerHolderProvider = Provider<TabContainerManagerHolder>(
  (ref) => TabContainerManagerHolder(),
  name: 'tabContainerManagerHolderProvider',
);
