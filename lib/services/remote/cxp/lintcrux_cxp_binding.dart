// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:lintcrux/services/remote/cxp/lintcrux_name_resolver.dart';

/// Who LintCrux is on CXP: its name, port, the element kinds it can show
/// when a peer asks, and the rule that screens a received path.
///
/// Everything else about the CXP lifecycle (starting the server, discovery,
/// the peer list, settings, acknowledgements) is the shared runtime's.
///
/// The server keeps the floor containment, the binding's default
/// (`kCxpOpenArtifactContainment` is the same value, and says why): one rule
/// screens both `request_open_source` and the hint of a
/// `request_open_artifact`, and the artifact request must not be rooted in the
/// directories the user has opened. The rooted rule for `request_open_source`
/// stays inside the request handler.
const CruxCxpProductBinding kLintcruxCxpBinding = CruxCxpProductBinding(
  productName: 'lintcrux',
  defaultPort: 54324,
  prefsPrefix: 'settings.',
  acceptedKinds: <ElementKind>[
    ElementKind.rule,
    ElementKind.source,
    ElementKind.signal,
    ElementKind.instance,
  ],
  nameResolver: LintCruxNameResolver(),
);
