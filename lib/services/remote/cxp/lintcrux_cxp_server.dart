// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:lintcrux/core/app_info/build_info.dart';
import 'package:lintcrux/services/remote/cxp/lintcrux_name_resolver.dart';

/// LintCrux-specific wrapper around [LocalCxpServer].
///
/// Owns the [PeerIdentity] LintCrux announces, registers
/// [LintCruxNameResolver] so inbound `RequestHighlight` /
/// `RequestOpenSource` envelopes resolve into LintCrux's local element
/// space, and forwards inbound messages to the handler callback the
/// receive-side lifecycle wires up. The wrapper exposes the start /
/// stop / port surface plus the wrapped [LocalCxpServer] (via [server],
/// for connector-link routing only) — feature code interacts with it
/// through the `cxpServerLifecycleProvider` rather than
/// reaching past the wrapper into [LocalCxpServer].
///
/// One server per running LintCrux process; the lifecycle provider
/// disposes the wrapper when the user disables the CXP server in
/// Settings → Remote Control or the app shuts down.
class LintCruxCxpServer {
  /// Creates a wrapper bound to [port] on `127.0.0.1`.
  ///
  /// [peerId] is the per-process unique ID written into the discovery
  /// manifest — caller supplies it so tests can pass a deterministic
  /// value. Production callers compute it from `pid` and
  /// `DateTime.now().millisecondsSinceEpoch` for uniqueness across
  /// concurrent LintCrux instances.
  ///
  /// [onInbound] is called for every CxpMessage the server accepts
  /// past the Hello / Subscribe / Unsubscribe / Goodbye handshake
  /// boundary (those four kinds are absorbed inside the server's
  /// internal dispatch — see `LocalCxpServer._PeerConnection._onLine`).
  /// The callback is expected to ack the message; if it does not, the
  /// requesting peer will time out client-side waiting for a reply.
  LintCruxCxpServer({
    required String peerId,
    required int port,
    required this.onInbound,
    Set<String> capabilities = const <String>{},
    CxpPathContainment? containment,
  }) : containment = containment ?? const CxpPathContainment(),
       _serverPort = port,
       _identity = PeerIdentity(
         peerId: peerId,
         productName: LintCruxBuildInfo.productName,
         productVersion: LintCruxBuildInfo.productVersion,
         capabilities: capabilities,
       );

  /// Computes the conventional LintCrux peer ID
  /// (`lintcrux-<pid>-<startedAtMillis>`).
  ///
  /// Static so tests that need a deterministic ID can construct a
  /// [LintCruxCxpServer] without going through this helper.
  static String makePeerId({
    required int pid,
    required int startedAtMillis,
  }) => '${LintCruxBuildInfo.productName}-$pid-$startedAtMillis';

  /// Called for every inbound CxpMessage past the handshake. The
  /// callback owns the ack — see [LintCruxCxpServer] docs.
  final void Function(InboundCxpMessage inbound) onInbound;

  /// The receiver-side rule (CXP §11) handed to [LocalCxpServer] so a
  /// `request_open_source` or a `request_open_artifact` hint is screened
  /// before [onInbound] ever sees it.
  ///
  /// The shared layer can only check the value that arrived on the wire; the
  /// value LintCrux is about to open, or hand to an editor argv, is checked
  /// after dispatch under the rule that route keeps. The default is the
  /// floor (absolute, well-formed), and the provider layer supplies the floor
  /// too: one rule screens both requests here, and the artifact request's
  /// hint must not be rooted in the directories the user has opened
  /// (`kCxpOpenArtifactContainment`).
  final CxpPathContainment containment;

  final int _serverPort;
  final PeerIdentity _identity;

  LocalCxpServer? _server;
  StreamSubscription<InboundCxpMessage>? _inboundSub;

  /// The peer identity the server announces in Hello and the discovery
  /// manifest. Exposed for tests and the cross-probe panel header.
  PeerIdentity get selfIdentity => _identity;

  /// The wrapped [LocalCxpServer], or `null` before [start] / after
  /// [stop].
  ///
  /// Exposed for one collaborator only: the receive-side lifecycle passes
  /// it to `CxpPeerConnector(server: ...)` so frames arriving over the
  /// connector's own client socket (a peer replying to us, or one we
  /// merely dialed) are merged into this server's dispatch stream and get
  /// a reply route. Without it, connector-link inbound is silently
  /// dropped. Feature code must still go through the lifecycle provider
  /// rather than reaching past the wrapper into [LocalCxpServer].
  LocalCxpServer? get server => _server;

  /// The bound port. Equal to the configured port after a successful
  /// [start]; `null` before [start] or after [stop]. Useful in tests
  /// that pass `port: 0` to let the OS pick a free port.
  int? get boundPort => _server?.boundPort;

  /// Whether the server is currently running.
  bool get isRunning => _server != null;

  /// Currently-connected peers (snapshot at call time).
  List<PeerIdentity> get connectedPeers =>
      _server?.connectedPeers ?? const <PeerIdentity>[];

  /// Stream of peer presence events emitted by the wrapped
  /// [LocalCxpServer]. Re-exposed unmodified so the cross-probe panel
  /// can render the live peer list without depending on
  /// `package:crux_cxp` directly.
  Stream<PeerPresenceEvent> get presence =>
      _server?.presence ?? const Stream<PeerPresenceEvent>.empty();

  /// Send [message] directly to [peerId]. Returns `true` when the peer
  /// is connected; `false` otherwise. Exposes the wrapped server's
  /// `sendTo` so the receive-side handler can deliver acks back to the
  /// originator.
  bool sendTo(String peerId, CxpMessage message) =>
      _server?.sendTo(peerId, message) ?? false;

  /// Sends [request] to [peerId] and waits for the peer's
  /// [RequestHighlightAck], so the cross-probe panel can surface a rejected
  /// send. Returns `(delivered: false, ack: null)` when stopped/unreachable, and
  /// `(delivered: true, ack: null)` when the send left but no ack arrived within
  /// [timeout]. Correlates by "the next RequestHighlightAck from [peerId]",
  /// unambiguous because such an ack only ever replies to a request_highlight
  /// and directed panel sends are the sole source of them.
  Future<({bool delivered, RequestHighlightAck? ack})> requestHighlight(
    String peerId,
    RequestHighlight request, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final server = _server;
    if (server == null) return (delivered: false, ack: null);
    final completer = Completer<RequestHighlightAck>();
    final sub = server.inbound.listen((inbound) {
      if (inbound.from.peerId == peerId &&
          inbound.message is RequestHighlightAck &&
          !completer.isCompleted) {
        completer.complete(inbound.message as RequestHighlightAck);
      }
    });
    final delivered = server.sendTo(peerId, request);
    if (!delivered) {
      await sub.cancel();
      return (delivered: false, ack: null);
    }
    RequestHighlightAck? ack;
    try {
      ack = await completer.future.timeout(timeout);
    } on TimeoutException {
      ack = null;
    } finally {
      await sub.cancel();
    }
    return (delivered: true, ack: ack);
  }

  /// Broadcasts [message] to every connected peer that subscribed to
  /// its [CxpMessage.kind]. No-op when the server is not running.
  ///
  /// Used by the Pro overlay's NotifySelection emitter to gossip
  /// selection events to other Crux peers (WaveCrux / NetCrux /
  /// SimCrux). The receive-side handlers for inbound NotifySelection
  /// ack with a generic "did not subscribe" payload, so peers that
  /// don't care about LintCrux selections silently filter the broadcast
  /// (the `peer.acceptsKind` check inside `LocalCxpServer.broadcast`).
  void broadcast(CxpMessage message) => _server?.broadcast(message);

  /// Starts the server. Safe to call when already running — second
  /// and later invocations are a no-op so the lifecycle provider can
  /// idempotently restart on settings churn.
  Future<void> start() async {
    if (_server != null) return;
    final server = LocalCxpServer(
      selfIdentity: _identity,
      nameResolver: const LintCruxNameResolver(),
      port: _serverPort,
      containment: containment,
    );
    await server.start();
    _server = server;
    _inboundSub = server.inbound.listen(onInbound);
  }

  /// Stops the server and releases its socket. Safe to call when not
  /// running. Returns after the underlying [LocalCxpServer.stop] has
  /// completed so the lifecycle provider can immediately rebind the
  /// port if the user changed it.
  Future<void> stop() async {
    final server = _server;
    if (server == null) return;
    _server = null;
    await _inboundSub?.cancel();
    _inboundSub = null;
    await server.stop();
  }
}
