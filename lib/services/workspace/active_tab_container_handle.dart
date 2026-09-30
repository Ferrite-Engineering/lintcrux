// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Services-layer handle resolving the ACTIVE tab's per-tab
/// `ProviderContainer` from root-scoped code that has no `BuildContext`.
///
/// Published by the feature-layer `WorkspaceRoot` on mount and cleared on
/// dispose — a legal `features → services` write (the same seam shape as
/// `CxpServerHandle`). Consumed by root-scoped services that must act on
/// the active tab's state — canonically the CXP inbound request path,
/// which receives a cross-probe message on the root-hosted server and
/// must read/mutate the ACTIVE tab's violation store, table state, and
/// selection rather than the empty root-scope instances.
///
/// The resolver returns `null` whenever no workspace is hydrated or no
/// tab is active; callers fall back to their own (root) scope in that
/// case, which matches the pre-workspace single-container behavior.
class ActiveTabContainerHandle {
  /// Resolver for the active tab's container, or `null` when no
  /// `WorkspaceRoot` is mounted. Set by `WorkspaceRoot` on mount and
  /// reset to `null` on dispose.
  ProviderContainer? Function()? resolver;

  /// The active tab's `ProviderContainer`, or `null` when no workspace
  /// root is mounted, the workspace has not hydrated, or no tab is
  /// active.
  ProviderContainer? get activeContainer => resolver?.call();
}

/// App-wide [ActiveTabContainerHandle]. Root-scoped by design — the
/// handle is the bridge FROM root scope INTO the active tab's scope.
final Provider<ActiveTabContainerHandle> activeTabContainerHandleProvider =
    Provider<ActiveTabContainerHandle>((ref) => ActiveTabContainerHandle());
