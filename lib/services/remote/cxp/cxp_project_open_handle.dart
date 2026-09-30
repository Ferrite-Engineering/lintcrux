// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Services-layer handle that opens a `.lintcrux` project from root-scoped code
/// that has no `BuildContext`.
///
/// Opening a project in a workspace tab needs the per-tab `ProviderContainer`
/// factory, which only the routed `WorkspaceRoot` can supply. `WorkspaceRoot`
/// publishes an [opener] here on mount and clears it on dispose — the same
/// `features → services` seam shape as `CxpServerHandle` and
/// `ActiveTabContainerHandle`. The root-hosted CXP inbound path consumes it to
/// open the design a peer named (via `request_open_artifact`, or on a
/// highlight it cannot satisfy locally).
///
/// [opener] is `null` whenever no `WorkspaceRoot` is mounted (headless / server
/// startup / unit tests); [open] then degrades to `false` so the CXP handler
/// acks the request gracefully instead of throwing.
///
/// The same seam carries the other half of that bridge: [projectPaths], the
/// projects the user has opened, which is what CXP §11's rooted rule needs
/// to know before the `crux.design_id` fallback may call [open]. (A
/// `request_open_artifact` is held to the floor instead:
/// `kCxpOpenArtifactContainment` says why.) Both live in the feature layer
/// (the workspace's tabs and the Recent projects list), so both cross into
/// root scope here.
class CxpProjectOpenHandle {
  /// Opens the `.lintcrux` project at the given absolute path in a new or
  /// focused workspace tab, returning whether it opened successfully. Set by
  /// `WorkspaceRoot` on mount, reset to `null` on dispose.
  Future<bool> Function(String path)? opener;

  /// The `.lintcrux` project files the user has opened: every workspace tab's
  /// plus the Recent projects list. Set by `WorkspaceRoot` on mount, reset to
  /// `null` on dispose; read on every call, so it reports live state.
  Iterable<String> Function()? projectPaths;

  /// Opens [path], returning `false` when no opener is currently published.
  Future<bool> open(String path) async => (await opener?.call(path)) ?? false;

  /// The current [projectPaths], or nothing when none is published.
  Iterable<String> get openedProjectPaths =>
      projectPaths?.call() ?? const <String>[];
}

/// App-wide [CxpProjectOpenHandle]. Root-scoped by design — the bridge FROM
/// root scope (the CXP inbound path) INTO the workspace's tab machinery.
final Provider<CxpProjectOpenHandle> cxpProjectOpenHandleProvider =
    Provider<CxpProjectOpenHandle>((ref) => CxpProjectOpenHandle());
