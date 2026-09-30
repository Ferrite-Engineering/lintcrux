// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/remote/providers/cxp_server_provider.dart'
    show lintCruxCxpSubscriptions;
import 'package:lintcrux/services/remote/cxp/lintcrux_cxp_server.dart';

import '../../../support/host_absolute_path.dart';

void main() {
  final servers = <LintCruxCxpServer>[];
  final clients = <LocalCxpClient>[];

  tearDown(() async {
    for (final c in clients) {
      try {
        await c.disconnect();
      } on Object {
        // best effort
      }
    }
    clients.clear();
    for (final s in servers) {
      await s.stop();
    }
    servers.clear();
  });

  LintCruxCxpServer makeServer({
    required void Function(InboundCxpMessage) onInbound,
    int port = 0,
    String peerId = 'lintcrux-test',
    CxpPathContainment? containment,
  }) {
    final s = LintCruxCxpServer(
      peerId: peerId,
      port: port,
      onInbound: onInbound,
      containment: containment,
    );
    servers.add(s);
    return s;
  }

  LocalCxpClient makeClient({
    String peerId = 'peer-1',
  }) {
    final c = LocalCxpClient(
      selfIdentity: PeerIdentity(
        peerId: peerId,
        productName: 'test-peer',
        productVersion: '0.0.1',
      ),
    );
    clients.add(c);
    return c;
  }

  group('LintCruxCxpServer', () {
    test('makePeerId formats lintcrux-<pid>-<startedAtMillis>', () {
      final id = LintCruxCxpServer.makePeerId(
        pid: 42,
        startedAtMillis: 1700000000000,
      );
      expect(id, 'lintcrux-42-1700000000000');
    });

    test('start binds a port and exposes the peer identity', () async {
      final received = <InboundCxpMessage>[];
      final server = makeServer(onInbound: received.add);
      expect(server.isRunning, isFalse);
      expect(server.boundPort, isNull);
      await server.start();
      expect(server.isRunning, isTrue);
      expect(server.boundPort, isNotNull);
      expect(server.boundPort, greaterThan(0));
      expect(server.selfIdentity.peerId, 'lintcrux-test');
      expect(server.selfIdentity.productName, 'lintcrux');
    });

    test('start is idempotent — second call is a no-op', () async {
      final server = makeServer(onInbound: (_) {});
      await server.start();
      final firstPort = server.boundPort;
      await server.start();
      expect(server.boundPort, firstPort);
    });

    test('stop releases the socket and is idempotent', () async {
      final server = makeServer(onInbound: (_) {});
      await server.start();
      await server.stop();
      expect(server.isRunning, isFalse);
      expect(server.boundPort, isNull);
      await server.stop();
    });

    test('forwards inbound RequestHighlight to onInbound', () async {
      final received = <InboundCxpMessage>[];
      final server = makeServer(onInbound: received.add);
      await server.start();
      final port = server.boundPort!;

      final client = makeClient();
      await client.connect(
        host: '127.0.0.1',
        port: port,
        token: cxpProcessAuthToken,
      );
      client.send(
        const RequestHighlight(
          element: ElementId(
            kind: ElementKind.source,
            path: '/x.sv:1',
          ),
        ),
      );

      await _pumpUntil(() => received.isNotEmpty);

      expect(received, hasLength(1));
      expect(received.single.message, isA<RequestHighlight>());
    });

    // The wrapper hands `containment` to `LocalCxpServer`, which screens the
    // path BEFORE dispatch: the refusal ack comes back and `onInbound` is
    // never called.
    //
    // MUTATION: dropping `containment: containment` from the
    // `LocalCxpServer` construction in `LintCruxCxpServer.start` makes this
    // red.
    test('refuses a file_path outside its roots without dispatching '
        'it', () async {
      final root = Directory.systemTemp.createTempSync('lintcrux_cxp_root_');
      addTearDown(() => root.deleteSync(recursive: true));
      final received = <InboundCxpMessage>[];
      final server = makeServer(
        onInbound: received.add,
        containment: CxpPathContainment(roots: () => <String>[root.path]),
      );
      await server.start();

      final clientInbound = <CxpMessage>[];
      final client = makeClient();
      client.inbound.listen((m) => clientInbound.add(m.message));
      await client.connect(
        host: '127.0.0.1',
        port: server.boundPort!,
        token: cxpProcessAuthToken,
      );
      final outside = hostAbsolute('/etc/shadow');
      client.send(RequestOpenSource(filePath: outside, line: 1));

      await _pumpUntil(
        () => clientInbound.any((m) => m is RequestOpenSourceAck),
      );
      final ack = clientInbound.whereType<RequestOpenSourceAck>().single;
      expect(ack.honored, isFalse);
      expect(ack.reason, contains('outside the directories'));
      expect(ack.reason, isNot(contains(outside)));
      expect(received, isEmpty);
    });

    // Wire 1.2's peer auth is inherited, not wired: the wrapper passes no
    // token, so `LocalCxpServer`'s default (require the process token) is
    // what LintCrux ships. This pins that default from the product side.
    test('a peer that does not present the token is refused', () async {
      final received = <InboundCxpMessage>[];
      final server = makeServer(onInbound: received.add);
      await server.start();

      final client = makeClient();
      await expectLater(
        client.connect(host: '127.0.0.1', port: server.boundPort!),
        throwsA(
          isA<CxpHandshakeException>().having(
            (e) => e.code,
            'code',
            CxpErrorCode.unauthorized,
          ),
        ),
      );
      expect(received, isEmpty);
    });

    test('broadcast on a not-running server is a no-op', () {
      final server = makeServer(onInbound: (_) {});
      // No throw — broadcast handles the not-started case so the Pro
      // overlay's NotifySelection emitter doesn't have to guard.
      expect(
        () => server.broadcast(
          const NotifySelection(
            elements: [
              ElementId(
                kind: ElementKind.rule,
                path: 'verilator/UNUSEDSIGNAL@/x.sv:1',
              ),
            ],
          ),
        ),
        returnsNormally,
      );
    });

    test('broadcast reaches a subscribed peer', () async {
      final server = makeServer(onInbound: (_) {});
      await server.start();
      final port = server.boundPort!;

      final clientInbound = <CxpMessage>[];
      final client = makeClient();
      client.inbound.listen((m) => clientInbound.add(m.message));
      await client.connect(
        host: '127.0.0.1',
        port: port,
        token: cxpProcessAuthToken,
      );

      // Subscribe explicitly — broadcast filters out peers that haven't
      // declared interest in the message kind.
      client.send(
        const Subscribe(
          subscriptions: [
            CxpSubscription(messageKind: 'notify_selection'),
          ],
        ),
      );

      // Give the subscribe time to propagate before broadcasting.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      server.broadcast(
        const NotifySelection(
          elements: [
            ElementId(
              kind: ElementKind.rule,
              path: 'verilator/UNUSEDSIGNAL@/x.sv:1',
            ),
          ],
        ),
      );

      await _pumpUntil(() => clientInbound.isNotEmpty);
      expect(clientInbound.single, isA<NotifySelection>());
    });

    test('sendTo delivers a message to a connected peer', () async {
      final received = <InboundCxpMessage>[];
      final server = makeServer(onInbound: received.add);
      await server.start();
      final port = server.boundPort!;

      final clientInbound = <CxpMessage>[];
      final client = makeClient();
      client.inbound.listen((m) => clientInbound.add(m.message));
      await client.connect(
        host: '127.0.0.1',
        port: port,
        token: cxpProcessAuthToken,
      );

      // Trigger a message inbound first so the server knows about us.
      client.send(
        const RequestHighlight(
          element: ElementId(
            kind: ElementKind.source,
            path: '/x.sv:1',
          ),
        ),
      );
      await _pumpUntil(() => received.isNotEmpty);

      final delivered = server.sendTo(
        'peer-1',
        const RequestHighlightAck(inReplyTo: 'm1', honored: true),
      );
      expect(delivered, isTrue);
      await _pumpUntil(() => clientInbound.isNotEmpty);
      expect(clientInbound.single, isA<RequestHighlightAck>());
    });
  });

  group('peer connector (mutual-connection regression)', () {
    test(
      'two LintCrux servers publishing into one shared manifest directory '
      'end up MUTUALLY CONNECTED via the peer connectors',
      () async {
        final dir = Directory.systemTemp.createTempSync('lintcrux_cxp_pair_');
        addTearDown(() => dir.deleteSync(recursive: true));

        Future<(LintCruxCxpServer, CxpDiscovery, CxpPeerConnector)> bringUp(
          String peerId,
        ) async {
          final server = makeServer(onInbound: (_) {}, peerId: peerId);
          await server.start();
          final writer = CxpManifestWriter(manifestDirectory: dir.path);
          addTearDown(writer.remove);
          await writer.write(
            identity: server.selfIdentity,
            host: '127.0.0.1',
            port: server.boundPort!,
          );
          final discovery = CxpDiscovery(
            manifestDirectory: dir.path,
            scanInterval: const Duration(milliseconds: 100),
          );
          addTearDown(discovery.stop);
          final connector = CxpPeerConnector(
            selfIdentity: server.selfIdentity,
            discovery: discovery,
            // Mirror production wiring (cxp_server_provider): route link
            // traffic into the wrapped server and narrow the announced
            // subscriptions. Without `server:` this test would exercise a
            // presence-only connector — the very bug the receive path had.
            server: server.server,
            subscriptions: lintCruxCxpSubscriptions,
            retryInterval: const Duration(milliseconds: 100),
          );
          addTearDown(connector.stop);
          await discovery.start();
          connector.start();
          return (server, discovery, connector);
        }

        // Anchor both peerIds to the REAL process pid (crux_cxp 0.4.2's
        // liveness prune reaps manifests whose embedded pid is a dead
        // process). Synthetic pids like `lintcrux-1-1` would be pruned mid
        // discovery and the peers would never become reachable. The distinct
        // startedAt suffixes keep the two identities apart.
        final peerIdA = 'lintcrux-$pid-1';
        final peerIdB = 'lintcrux-$pid-2';
        final (a, _, _) = await bringUp(peerIdA);
        final (b, _, _) = await bringUp(peerIdB);

        // Pre-fix, discovery surfaced the manifests but no CXP socket was
        // ever opened, so both connectedPeers lists stayed empty forever.
        await _pumpUntil(
          () =>
              a.connectedPeers.any((p) => p.peerId == peerIdB) &&
              b.connectedPeers.any((p) => p.peerId == peerIdA),
          timeout: const Duration(seconds: 10),
        );
      },
    );
  });
}

Future<void> _pumpUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Predicate not satisfied within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
