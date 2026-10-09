// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_window_chrome/crux_window_chrome.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/app_settings.dart';
import 'package:lintcrux/domain/models/editor/editor_command.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/services/editor/click_to_source_service.dart';
import 'package:lintcrux/services/editor/editor_command_provider.dart';
import 'package:lintcrux/services/remote/cxp/cxp_project_open_handle.dart';
import 'package:lintcrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:lintcrux/services/remote/cxp/lintcrux_name_resolver.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../support/host_absolute_path.dart';
import '../../support/host_independent_editor_resolver.dart';
import '../../support/noop_process.dart';
import '../../support/telemetry_test_store.dart';

/// Editor launcher that records its calls and never actually spawns a
/// real editor. `launch` hands back a [NoopProcess] so the surrounding
/// `ClickToSourceService` reports success.
class RecordingLauncher implements EditorLauncher {
  /// Calls received, oldest first. Each entry is `[executable, ...args]`.
  final List<List<String>> calls = <List<String>>[];

  /// Set to false to make the launcher throw and the
  /// `ClickToSourceService` report failure.
  bool succeed = true;

  @override
  Future<Process> launch(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) async {
    calls.add(<String>[executable, ...arguments]);
    if (!succeed) {
      throw const ProcessException('exec', <String>[], 'launch failed');
    }
    return const NoopProcess();
  }
}

class _SeedSettingsNotifier extends AppSettingsNotifier {
  _SeedSettingsNotifier(this._seed);

  final AppSettings _seed;

  @override
  AppSettings build() => _seed;
}

ProviderContainer buildContainer({
  required String manifestDir,
  required InMemoryViolationStore store,
  required RecordingLauncher launcher,
  int port = 0,
  bool enabled = true,
  List<String>? openedProjects,
  CxpProjectOpenHandle? openHandle,
  CxpWorkspaceStore? workspaceStore,
}) {
  return ProviderContainer(
    overrides: <Override>[
      ...telemetryDeclinedOverrides(),
      if (workspaceStore != null)
        cxpWorkspaceStoreProvider.overrideWithValue(workspaceStore),
      // The projects the user has opened, as `WorkspaceRoot` would publish
      // them. This container mounts no workspace, so without it the
      // production containment rule (CXP §11) would see nothing open and
      // refuse every peer-supplied path. Overriding the HANDLE rather than
      // `cxpPathContainmentProvider` keeps the production roots function in
      // the path under test.
      cxpProjectOpenHandleProvider.overrideWithValue(
        (openHandle ?? CxpProjectOpenHandle())
          ..projectPaths = () =>
              openedProjects ??
              <String>[hostAbsolute('/proj/project.lintcrux')],
      ),
      appSettingsProvider.overrideWith(
        () => _SeedSettingsNotifier(
          AppSettings(
            cxpServerEnabled: enabled,
            cxpServerPort: port,
          ),
        ),
      ),
      violationStoreProvider.overrideWithValue(store),
      cxpManifestDirectoryProvider.overrideWith((ref) async => manifestDir),
      clickToSourceServiceProvider.overrideWithValue(
        ClickToSourceService(
          commandFor: () => EditorCommand.vsCode,
          launcher: launcher,
          resolver: hostIndependentEditorResolver,
        ),
      ),
    ],
  );
}

Future<void> _pumpUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Predicate not satisfied within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
  late Directory tempDir;
  late InMemoryViolationStore store;
  late RecordingLauncher launcher;
  ProviderContainer? container;
  LocalCxpClient? client;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('lintcrux_cxp_test_');
    store = InMemoryViolationStore();
    launcher = RecordingLauncher();
    // The inbound path fires `requestUserAttention()` on a honored ack.
    // These are plain `test()` bodies with no Flutter binding, so the default
    // method-channel requester would throw "Binding has not yet been
    // initialized". Swap to the no-op backend — exactly what the production
    // attention gate does when the setting is off — so attention is a safe
    // no-op here.
    windowAttentionRequester = const NoopWindowAttentionRequester();
  });

  tearDown(() async {
    windowAttentionRequester = const MethodChannelWindowAttentionRequester();
    if (client != null) {
      try {
        await client!.disconnect();
      } on Object {
        // best effort
      }
    }
    container?.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('cxpServerLifecycleProvider', () {
    test('starts when enabled and writes a discovery manifest', () async {
      container = buildContainer(
        manifestDir: tempDir.path,
        store: store,
        launcher: launcher,
      );
      final state = await container!.read(
        cxpServerLifecycleProvider.future,
      );
      expect(state.running, isTrue);
      expect(state.boundPort, isNotNull);
      expect(state.peerId, isNotNull);

      await _pumpUntil(
        () => Directory(
          tempDir.path,
        ).listSync().whereType<File>().any((f) => f.path.endsWith('.json')),
      );
    });

    test('does not start when disabled', () async {
      container = buildContainer(
        manifestDir: tempDir.path,
        store: store,
        launcher: launcher,
        enabled: false,
      );
      final state = await container!.read(
        cxpServerLifecycleProvider.future,
      );
      expect(state.running, isFalse);
      expect(state.boundPort, isNull);
    });

    test('end-to-end RequestHighlight rule kind selects the violation '
        'and clears filters', () async {
      const v = Violation(
        engineId: 'verilator',
        ruleId: 'verilator/UNUSEDSIGNAL',
        severity: Severity.warning,
        message: 'unused',
        location: SourceLocation(
          file: '/proj/cpu.sv',
          line: 42,
          column: 7,
        ),
      );
      store.replaceFromEngine('verilator', [v]);

      container = buildContainer(
        manifestDir: tempDir.path,
        store: store,
        launcher: launcher,
      );
      final state = await container!.read(
        cxpServerLifecycleProvider.future,
      );
      container!
          .read(violationTableStateProvider.notifier)
          .toggleSeverity(Severity.error);

      client = LocalCxpClient(
        selfIdentity: const PeerIdentity(
          peerId: 'peer-wave',
          productName: 'wavecrux',
          productVersion: '0.7.0',
        ),
      );
      final clientAcks = <CxpMessage>[];
      client!.inbound.listen((m) => clientAcks.add(m.message));
      await client!.connect(
        host: '127.0.0.1',
        port: state.boundPort!,
        token: cxpProcessAuthToken,
      );

      client!.send(
        RequestHighlight(
          element: ElementId(
            kind: ElementKind.rule,
            path: LintCruxNameResolver.encodeViolationAsRulePath(v)!,
          ),
        ),
      );

      await _pumpUntil(() => clientAcks.isNotEmpty);
      expect(clientAcks.single, isA<RequestHighlightAck>());
      final ack = clientAcks.single as RequestHighlightAck;
      expect(ack.honored, isTrue);

      final table = container!.read(violationTableStateProvider);
      expect(table.severities, isEmpty);
      expect(container!.read(selectedViolationProvider), v);
    });

    test('end-to-end RequestOpenSource shells out via the launcher', () async {
      container = buildContainer(
        manifestDir: tempDir.path,
        store: store,
        launcher: launcher,
      );
      final state = await container!.read(
        cxpServerLifecycleProvider.future,
      );

      client = LocalCxpClient(
        selfIdentity: const PeerIdentity(
          peerId: 'peer-net',
          productName: 'netcrux',
          productVersion: '0.5.0',
        ),
      );
      final clientAcks = <CxpMessage>[];
      client!.inbound.listen((m) => clientAcks.add(m.message));
      await client!.connect(
        host: '127.0.0.1',
        port: state.boundPort!,
        token: cxpProcessAuthToken,
      );

      client!.send(
        RequestOpenSource(
          filePath: hostAbsolute('/proj/cpu.sv'),
          line: 42,
          column: 7,
        ),
      );

      await _pumpUntil(() => clientAcks.isNotEmpty);
      expect(clientAcks.single, isA<RequestOpenSourceAck>());
      final ack = clientAcks.single as RequestOpenSourceAck;
      expect(ack.honored, isTrue);
      expect(launcher.calls, hasLength(1));
    });

    // CXP §11 through the production wiring: the roots are the directories
    // of the projects the user opened (the handle `WorkspaceRoot` publishes),
    // and an absolute path outside them is refused before any editor runs.
    test('refuses a RequestOpenSource outside the opened projects without '
        'launching an editor', () async {
      container = buildContainer(
        manifestDir: tempDir.path,
        store: store,
        launcher: launcher,
      );
      final state = await container!.read(
        cxpServerLifecycleProvider.future,
      );

      client = LocalCxpClient(
        selfIdentity: const PeerIdentity(
          peerId: 'peer-net',
          productName: 'netcrux',
          productVersion: '0.5.0',
        ),
      );
      final clientAcks = <CxpMessage>[];
      client!.inbound.listen((m) => clientAcks.add(m.message));
      await client!.connect(
        host: '127.0.0.1',
        port: state.boundPort!,
        token: cxpProcessAuthToken,
      );

      final outside = hostAbsolute('/etc/passwd');
      client!.send(RequestOpenSource(filePath: outside, line: 1));

      await _pumpUntil(() => clientAcks.isNotEmpty);
      final ack = clientAcks.single as RequestOpenSourceAck;
      expect(ack.honored, isFalse);
      expect(ack.reason, contains('outside the directories'));
      // CXP §9.11: the reason never echoes the sender's path back.
      expect(ack.reason, isNot(contains(outside)));
      expect(launcher.calls, isEmpty);
    });

    // `request_open_artifact` through the production wiring. It is held to
    // the floor, not the opened projects: it exists to open a project
    // LintCrux has never opened, which is what "Open in LintCrux Desktop" in
    // VS Code sends (`kCxpOpenArtifactContainment` says why). So a recorded
    // project outside the opened ones is opened too. The route's refusals,
    // and the `crux.design_id` fallback that keeps the roots, are in
    // `cxp_open_artifact_test.dart`.
    //
    // MUTATION: checking the path with `cxpPathContainmentProvider` in
    // `openRequestedArtifact` instead of `kCxpOpenArtifactContainment` makes the
    // outside project refused, and this goes red.
    test('RequestOpenArtifact opens a recorded project inside the opened '
        'projects, and one outside them under the floor', () async {
      final inside = Directory.systemTemp.createTempSync('lintcrux_cxp_in_');
      final outside = Directory.systemTemp.createTempSync('lintcrux_cxp_out_');
      final records = Directory.systemTemp.createTempSync('lintcrux_cxp_ws_');
      addTearDown(() {
        for (final dir in <Directory>[inside, outside, records]) {
          dir.deleteSync(recursive: true);
        }
      });
      final insideProject = File('${inside.path}/project.lintcrux')
        ..writeAsStringSync('{}');
      final outsideProject = File('${outside.path}/project.lintcrux')
        ..writeAsStringSync('{}');
      final workspace = CxpWorkspaceStore(workspaceDirectory: records.path);
      for (final project in <File>[insideProject, outsideProject]) {
        await workspace.upsertArtifact(
          designId: cxpDesignIdForPath(project.path),
          kind: kCxpLintcruxSourceKind,
          path: project.path,
          producer: 'peer',
        );
      }
      final opened = <String>[];
      container = buildContainer(
        manifestDir: tempDir.path,
        store: store,
        launcher: launcher,
        openedProjects: <String>[insideProject.path],
        workspaceStore: workspace,
        openHandle: CxpProjectOpenHandle()
          ..opener = (path) async {
            opened.add(path);
            return true;
          },
      );
      final state = await container!.read(
        cxpServerLifecycleProvider.future,
      );

      client = LocalCxpClient(
        selfIdentity: const PeerIdentity(
          peerId: 'peer-sim',
          productName: 'simcrux',
          productVersion: '0.5.0',
        ),
      );
      final clientAcks = <CxpMessage>[];
      client!.inbound.listen((m) => clientAcks.add(m.message));
      await client!.connect(
        host: '127.0.0.1',
        port: state.boundPort!,
        token: cxpProcessAuthToken,
      );

      client!.send(
        RequestOpenArtifact(
          designId: cxpDesignIdForPath(outsideProject.path),
          artifactKind: kCxpLintcruxSourceKind,
        ),
      );
      await _pumpUntil(() => clientAcks.isNotEmpty);
      final outsideAck = clientAcks.single as RequestOpenArtifactAck;
      expect(outsideAck.honored, isTrue, reason: outsideAck.reason);
      expect(opened, <String>[outsideProject.path]);

      client!.send(
        RequestOpenArtifact(
          designId: cxpDesignIdForPath(insideProject.path),
          artifactKind: kCxpLintcruxSourceKind,
        ),
      );
      await _pumpUntil(() => clientAcks.length == 2);
      expect((clientAcks.last as RequestOpenArtifactAck).honored, isTrue);
      expect(opened, <String>[outsideProject.path, insideProject.path]);
    });

    // The `crux.design_id` fallback reads records through this store, so it
    // has to carry the rooted rule. (The server screens the wire with the
    // floor: see `kCxpOpenArtifactContainment`.)
    test('the workspace store carries the rooted containment rule', () {
      container = buildContainer(
        manifestDir: tempDir.path,
        store: store,
        launcher: launcher,
      );
      expect(
        container!.read(cxpWorkspaceStoreProvider).containment,
        same(container!.read(cxpPathContainmentProvider)),
      );
    });

    test('discovers peers that appear in the manifest directory', () async {
      container = buildContainer(
        manifestDir: tempDir.path,
        store: store,
        launcher: launcher,
      );
      await container!.read(cxpServerLifecycleProvider.future);

      // Anchor the fake peer's id to the REAL process pid: crux_cxp 0.4.2's
      // liveness prune reaps manifests whose embedded pid is a dead process,
      // so a synthetic pid (`wavecrux-99-9`) would be pruned before discovery
      // could surface it.
      final fakePeerId = 'wavecrux-$pid-9';
      final fakePath = '${tempDir.path}/$fakePeerId.json';
      File(fakePath).writeAsStringSync(
        _jsonEncode(<String, Object?>{
          'identity': <String, Object?>{
            'peer_id': fakePeerId,
            'product_name': 'wavecrux',
            'product_version': '0.7.0',
            'capabilities': <String>[],
          },
          'host': '127.0.0.1',
          'port': 54322,
          'started_at': DateTime.now().toUtc().millisecondsSinceEpoch,
        }),
      );

      await _pumpUntil(
        () => container!
            .read(cxpPeersProvider)
            .any((p) => p.identity.peerId == fakePeerId),
        timeout: const Duration(seconds: 4),
      );

      File(fakePath).deleteSync();
      await _pumpUntil(
        () => container!
            .read(cxpPeersProvider)
            .every((p) => p.identity.peerId != fakePeerId),
        timeout: const Duration(seconds: 4),
      );
    });

    test('turning the server off empties the peer list', () async {
      // The setter persists; give it an in-memory preferences store.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      container = buildContainer(
        manifestDir: tempDir.path,
        store: store,
        launcher: launcher,
      );
      await container!.read(cxpServerLifecycleProvider.future);

      // A live pid, for the reason the discovery test above gives.
      final fakePeerId = 'vscode-$pid-7';
      File('${tempDir.path}/$fakePeerId.json').writeAsStringSync(
        _jsonEncode(<String, Object?>{
          'identity': <String, Object?>{
            'peer_id': fakePeerId,
            'product_name': 'vscode',
            'product_version': '1.0.0',
            'capabilities': <String>[],
          },
          'host': '127.0.0.1',
          'port': 54329,
          'started_at': DateTime.now().toUtc().millisecondsSinceEpoch,
        }),
      );
      await _pumpUntil(
        () => container!.read(cxpPeersProvider).isNotEmpty,
        timeout: const Duration(seconds: 4),
      );

      // The peer's manifest stays on disk: only the server is turned off.
      container!
          .read(appSettingsProvider.notifier)
          .setCxpServerEnabled(enabled: false);
      final state = await container!.read(cxpServerLifecycleProvider.future);
      expect(state.running, isFalse);
      expect(
        container!.read(cxpPeersProvider),
        isEmpty,
        reason:
            'a stopped server must not keep reporting peers (the '
            'toolbar badge counts this list)',
      );
    });

    test(
      'surfaces a discovered-but-unreachable peer via '
      'cxpDialFailuresProvider',
      () async {
        // Reserve then release a loopback port so nothing is listening on
        // it — a dial to it fails deterministically (connection refused)
        // instead of racing a real peer's startup.
        final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final deadPort = probe.port;
        await probe.close();

        container = buildContainer(
          manifestDir: tempDir.path,
          store: store,
          launcher: launcher,
        );
        await container!.read(cxpServerLifecycleProvider.future);

        // Publish a peer manifest pointing at the dead port. The connector
        // dials it immediately on discovery, the dial fails, and the
        // lifecycle refreshes cxpDialFailuresProvider from the connector's
        // per-peer failure map.
        final deadPath = '${tempDir.path}/wavecrux-dead-1.json';
        File(deadPath).writeAsStringSync(
          _jsonEncode(<String, Object?>{
            'identity': <String, Object?>{
              'peer_id': 'wavecrux-dead-1',
              'product_name': 'wavecrux',
              'product_version': '0.7.0',
              'capabilities': <String>[],
            },
            'host': '127.0.0.1',
            'port': deadPort,
            'started_at': DateTime.now().toUtc().millisecondsSinceEpoch,
          }),
        );

        await _pumpUntil(
          () => container!
              .read(cxpDialFailuresProvider)
              .any((f) => f.peerId == 'wavecrux-dead-1'),
          timeout: const Duration(seconds: 6),
        );

        final failure = container!
            .read(cxpDialFailuresProvider)
            .firstWhere((f) => f.peerId == 'wavecrux-dead-1');
        expect(failure.port, deadPort);
        expect(failure.consecutiveFailures, greaterThanOrEqualTo(1));
      },
    );

    test(
      'sendTo delivers a targeted message to a connected peer '
      '(Pro origination seam)',
      () async {
        container = buildContainer(
          manifestDir: tempDir.path,
          store: store,
          launcher: launcher,
        );
        final state = await container!.read(
          cxpServerLifecycleProvider.future,
        );

        client = LocalCxpClient(
          selfIdentity: const PeerIdentity(
            peerId: 'peer-wave-sendto',
            productName: 'wavecrux',
            productVersion: '0.7.0',
            // The client only receives messages whose kind it advertises.
            capabilities: <String>{'notify_selection'},
          ),
        );
        final clientInbound = <CxpMessage>[];
        client!.inbound.listen((m) => clientInbound.add(m.message));
        await client!.connect(
          host: '127.0.0.1',
          port: state.boundPort!,
          token: cxpProcessAuthToken,
        );

        // Wait for the server to see the connected peer before we send.
        await _pumpUntil(() {
          // The lifecycle event log records peerConnected when the
          // server's presence stream sees the client.
          return container!
              .read(cxpEventLogProvider)
              .entries
              .any(
                (e) => e.kind == CxpEventKind.peerConnected,
              );
        });

        final delivered = container!
            .read(cxpServerLifecycleProvider.notifier)
            .sendTo(
              'peer-wave-sendto',
              const NotifySelection(
                elements: <ElementId>[
                  ElementId(
                    kind: ElementKind.rule,
                    path: 'verilator/UNUSEDSIGNAL@/proj/cpu.sv:1:1',
                  ),
                ],
                displayName: 'targeted dispatch',
              ),
            );
        expect(delivered, isTrue);
        await _pumpUntil(() => clientInbound.isNotEmpty);
        expect(clientInbound.single, isA<NotifySelection>());
      },
    );

    test(
      "a RequestHighlight arriving purely over LintCrux's own connector "
      'link (not a socket the remote dialed into us) reaches the request '
      'handler and the ack returns over the same link',
      () async {
        const v = Violation(
          engineId: 'verilator',
          ruleId: 'verilator/UNUSEDSIGNAL',
          severity: Severity.warning,
          message: 'unused',
          location: SourceLocation(
            file: '/proj/cpu.sv',
            line: 42,
            column: 7,
          ),
        );
        store.replaceFromEngine('verilator', [v]);

        container = buildContainer(
          manifestDir: tempDir.path,
          store: store,
          launcher: launcher,
        );
        final state = await container!.read(
          cxpServerLifecycleProvider.future,
        );

        // A remote peer (playing e.g. WaveCrux) publishing a manifest into
        // the shared directory. LintCrux's OWN connector (started inside the
        // lifecycle build) must discover and dial it — no connector on the
        // remote side. The frame the remote later sends therefore travels
        // exclusively over the socket LintCrux's connector opened. Without
        // `server:` wired into that connector, the frame lands on the
        // connector's own client socket and never reaches the handler.
        const remoteIdentity = PeerIdentity(
          peerId: 'wavecrux-link-req',
          productName: 'wavecrux',
          productVersion: '0.7.0',
        );
        final remote = LocalCxpServer(selfIdentity: remoteIdentity);
        await remote.start();
        addTearDown(remote.stop);
        final remoteInbound = <InboundCxpMessage>[];
        remote.inbound.listen(remoteInbound.add);
        final remoteWriter = CxpManifestWriter(
          manifestDirectory: tempDir.path,
          heartbeatInterval: const Duration(milliseconds: 100),
        );
        addTearDown(remoteWriter.remove);
        await remoteWriter.write(
          identity: remoteIdentity,
          host: '127.0.0.1',
          port: remote.boundPort!,
        );

        // LintCrux's connector dialed the remote — the remote's server now
        // sees LintCrux connected.
        await _pumpUntil(
          () => remote.connectedPeers.any((p) => p.peerId == state.peerId),
          timeout: const Duration(seconds: 8),
        );

        // The connector announced its narrowed subscription set: the two
        // request kinds LintCrux honours, and NOT notify_selection (so peer
        // gossip never reaches the handler to be answered with an error).
        await _pumpUntil(
          () => remote.debugSubscriptionsOf(state.peerId!).isNotEmpty,
          timeout: const Duration(seconds: 8),
        );
        final announced = remote
            .debugSubscriptionsOf(state.peerId!)
            .map((s) => s.messageKind)
            .toSet();
        expect(announced, contains(CxpMessageKind.requestHighlight));
        expect(announced, contains(CxpMessageKind.requestOpenSource));
        expect(announced, isNot(contains(CxpMessageKind.notifySelection)));

        // The remote sends a RequestHighlight over the socket it accepted
        // from LintCrux's connector.
        final delivered = remote.sendTo(
          state.peerId!,
          RequestHighlight(
            element: ElementId(
              kind: ElementKind.rule,
              path: LintCruxNameResolver.encodeViolationAsRulePath(v)!,
            ),
          ),
        );
        expect(delivered, isTrue);

        // The ack returns to the remote over the same link — proof the
        // frame reached the handler, not merely the connector's socket.
        await _pumpUntil(
          () => remoteInbound.any((m) => m.message is RequestHighlightAck),
          timeout: const Duration(seconds: 8),
        );
        final ack =
            remoteInbound
                    .firstWhere((m) => m.message is RequestHighlightAck)
                    .message
                as RequestHighlightAck;
        expect(ack.honored, isTrue);

        // The handler actually acted: the matched violation is selected.
        expect(container!.read(selectedViolationProvider), v);
      },
    );

    test(
      'sendTo returns false when the peer is not connected',
      () async {
        container = buildContainer(
          manifestDir: tempDir.path,
          store: store,
          launcher: launcher,
        );
        await container!.read(cxpServerLifecycleProvider.future);

        final delivered = container!
            .read(cxpServerLifecycleProvider.notifier)
            .sendTo(
              'no-such-peer',
              const NotifySelection(
                elements: <ElementId>[
                  ElementId(kind: ElementKind.rule, path: 'x@/y.sv:1:1'),
                ],
              ),
            );
        expect(delivered, isFalse);
      },
    );

    test(
      'sendTo returns false when the server is not running',
      () async {
        container = buildContainer(
          manifestDir: tempDir.path,
          store: store,
          launcher: launcher,
          enabled: false,
        );
        await container!.read(cxpServerLifecycleProvider.future);

        final delivered = container!
            .read(cxpServerLifecycleProvider.notifier)
            .sendTo(
              'unreachable',
              const NotifySelection(
                elements: <ElementId>[
                  ElementId(kind: ElementKind.rule, path: 'x@/y.sv:1:1'),
                ],
              ),
            );
        expect(delivered, isFalse);
      },
    );
  });
}

String _jsonEncode(Map<String, Object?> map) {
  final buf = StringBuffer('{');
  var first = true;
  map.forEach((k, v) {
    if (!first) buf.write(',');
    first = false;
    buf.write('"$k":');
    if (v is String) {
      buf.write('"$v"');
    } else if (v is num || v is bool) {
      buf.write('$v');
    } else if (v is Map) {
      buf.write(_jsonEncode(v.cast<String, Object?>()));
    } else if (v is List) {
      buf.write('[');
      for (var i = 0; i < v.length; i++) {
        if (i > 0) buf.write(',');
        final entry = v[i];
        if (entry is String) {
          buf.write('"$entry"');
        } else {
          buf.write('$entry');
        }
      }
      buf.write(']');
    } else if (v == null) {
      buf.write('null');
    } else {
      buf.write('"$v"');
    }
  });
  buf.write('}');
  return buf.toString();
}
