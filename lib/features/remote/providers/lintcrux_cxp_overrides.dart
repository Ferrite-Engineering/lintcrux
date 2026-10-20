// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_window_chrome/crux_window_chrome.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:lintcrux/core/app_info/about_providers.dart';
import 'package:lintcrux/features/remote/providers/cxp_request_handler_provider.dart';
import 'package:lintcrux/services/remote/cxp/lintcrux_cxp_binding.dart';

/// The root `ProviderScope` overrides that bind LintCrux to the shared CXP
/// lifecycle in `crux_cxp_ui`: who it is, the settings it loaded before
/// `runApp`, what it does when a peer asks, the version it reports and the
/// window attention it requests.
///
/// Spread before the overlay's overrides so the overlay can still replace any
/// of them.
List<Override> lintcruxCxpOverrides({
  required CruxCxpSettings launchSettings,
}) => <Override>[
  cruxCxpProductBindingProvider.overrideWithValue(kLintcruxCxpBinding),
  cruxCxpLaunchSettingsProvider.overrideWithValue(launchSettings),
  cruxCxpRequestHandlerProvider.overrideWith(LintCruxCxpWrappedHandler.new),
  cruxCxpProductVersionProvider.overrideWith((ref) async {
    try {
      return (await ref.watch(aboutBuildInfoProvider.future)).version;
    } on Object {
      return 'dev';
    }
  }),
  cruxCxpAttentionRequesterProvider.overrideWithValue(requestUserAttention),
  // The one place the outbound `cxp.crossprobe` funnel event is recorded, for
  // every send from every surface. A send that never left (denied, nothing
  // selected, the server off, no peer running) is not a funnel step.
  crossProbeSendObserverProvider.overrideWith(
    (ref) => (record) {
      switch (record.outcome.kind) {
        case CrossProbeOutcomeKind.denied:
        case CrossProbeOutcomeKind.nothingSelected:
        case CrossProbeOutcomeKind.serverOff:
        case CrossProbeOutcomeKind.noPeers:
          return;
        case CrossProbeOutcomeKind.sent:
        case CrossProbeOutcomeKind.refused:
        case CrossProbeOutcomeKind.noResponse:
        case CrossProbeOutcomeKind.peerGone:
        case CrossProbeOutcomeKind.notShowable:
          break;
      }
      ref
          .read(telemetryServiceProvider)
          .record(
            TelemetryEvent(
              'cxp.crossprobe',
              properties: <String, Object?>{
                'direction': 'outbound',
                'honored': record.outcome.kind == CrossProbeOutcomeKind.sent,
              },
            ),
          );
    },
  ),
];
