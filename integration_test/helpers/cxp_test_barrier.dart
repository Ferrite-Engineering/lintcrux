// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/helpers/cxp_test_barrier.dart
//
// In-band synchronization barrier for CXP socket integration tests.
// Ported from netcrux's integration helper of the same name (it only
// depends on `crux_cxp`, so it ports verbatim apart from the probe-kind
// prefix). Self-contained, matching how every other integration helper
// in this directory stays importable without crossing the test/ boundary.
//
// Replaces the "sleep and hope" pattern after fire-and-forget sends
// (`Hello` / `Subscribe` have no ack in the v1 protocol) with a
// deterministic round-trip: the server's per-connection read loop is
// FIFO, so once the reply to a probe sent AFTER a `Subscribe` arrives,
// the earlier messages (Hello registration + Subscribe) are guaranteed
// processed server-side.

import 'package:crux_cxp/crux_cxp.dart';

int _probeCounter = 0;

class _BarrierProbe extends CxpMessage {
  const _BarrierProbe(this._kind);

  final String _kind;

  @override
  String get kind => _kind;

  @override
  Map<String, Object?> toJson() => const <String, Object?>{};
}

/// Round-trip barrier: returns once the server has processed every
/// message [client] sent before this call.
///
/// Sends a unique unknown-kind probe and awaits the matching
/// `ErrorResponse(unknownKind)` (the server names the offending kind in
/// the error message, so concurrent barriers can't cross-match). The v1
/// protocol has no `SubscribeAck`; this is the deterministic equivalent.
Future<void> cxpRoundTripBarrier(
  LocalCxpClient client, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final probeKind = 'lintcrux_it_barrier_${_probeCounter++}';
  final reply = client.inbound.firstWhere((inbound) {
    final message = inbound.message;
    return message is ErrorResponse &&
        message.code == CxpErrorCode.unknownKind &&
        message.message.contains(probeKind);
  });
  client.send(_BarrierProbe(probeKind));
  await reply.timeout(timeout);
}
