// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/services/remote/cxp/lintcrux_cxp_server.dart';

/// Services-layer handle to the running CXP server.
///
/// Published by the **feature**-layer server lifecycle
/// (`CxpServerLifecycle`) when the server starts, and cleared on teardown
/// — a legal `features → services` write. Consumed by **services**-layer
/// originators (e.g. the Pro cross-probe originator) so they can dispatch
/// outbound CXP messages without importing the feature-layer
/// `cxpServerLifecycleProvider` — the seam described in ARCHITECTURE.md
/// §6.2.
///
/// Holds `null` whenever no server is running, so a non-null [server] also
/// means "the server is up".
class CxpServerHandle {
  /// The running server, or `null` when no server is running. Set by the
  /// feature server lifecycle on start / teardown; read by services-layer
  /// originators.
  LintCruxCxpServer? server;
}

/// App-wide [CxpServerHandle]. Open-core; the feature lifecycle populates
/// it and services-layer originators read it.
final Provider<CxpServerHandle> cxpServerHandleProvider =
    Provider<CxpServerHandle>((ref) => CxpServerHandle());
