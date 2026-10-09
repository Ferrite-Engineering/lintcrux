// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_project/crux_project.dart' show CruxProjectParser;
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_window_chrome/crux_window_chrome.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/app_settings.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/workspace/services/crux_project_resolution.dart';
import 'package:lintcrux/services/editor/editor_command_provider.dart';
import 'package:lintcrux/services/remote/cxp/cxp_outbound.dart';
import 'package:lintcrux/services/remote/cxp/cxp_paths.dart';
import 'package:lintcrux/services/remote/cxp/cxp_project_open_handle.dart';
import 'package:lintcrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:lintcrux/services/remote/cxp/lintcrux_cxp_request_handler.dart';
import 'package:lintcrux/services/remote/cxp/lintcrux_cxp_server.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';
import 'package:lintcrux/services/workspace/active_tab_container_handle.dart';
import 'package:meta/meta.dart';

/// Broadcast subscriptions the LintCrux peer connector announces to
/// peers after each handshake.
///
/// LintCrux acts only on point-to-point `RequestHighlight` /
/// `RequestOpenSource` (see [LintCruxCxpRequestHandler]) and consumes no
/// broadcast gossip. Subscribing to the full [cxpSubscribeToAll] set —
/// which includes `notify_selection` — would make every peer forward its
/// selection gossip here, and the receive handler would answer each frame
/// with `ErrorResponse(unsupported)`. Narrowing to the two request kinds
/// LintCrux honours keeps that gossip off the wire entirely. Point-to-point
/// requests and their acks are addressed directly and are unaffected by
/// this list.
const List<CxpSubscription> lintCruxCxpSubscriptions = <CxpSubscription>[
  CxpSubscription(messageKind: CxpMessageKind.requestHighlight),
  CxpSubscription(messageKind: CxpMessageKind.requestOpenSource),
];

/// Configuration snapshot the lifecycle binds to. Re-derived from
/// `appSettingsProvider` whenever the user toggles the enabled flag or
/// changes the port. Equality is value-based so a no-op settings save
/// does not cycle the server.
@immutable
class CxpServerConfig {
  /// Creates a config snapshot.
  const CxpServerConfig({
    required this.enabled,
    required this.port,
  });

  /// Whether the server should be running.
  final bool enabled;

  /// Port the server should bind to on `127.0.0.1`.
  final int port;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CxpServerConfig &&
          other.enabled == enabled &&
          other.port == port);

  @override
  int get hashCode => Object.hash(enabled, port);
}

/// Provider exposing the [CxpServerConfig] derived from app settings.
///
/// The lifecycle provider watches this so it only restarts the server
/// when either the enabled flag or the port actually changed — not on
/// every unrelated settings mutation.
final Provider<CxpServerConfig> cxpServerConfigProvider =
    Provider<CxpServerConfig>((ref) {
      final settings = ref.watch(appSettingsProvider);
      return CxpServerConfig(
        enabled: settings.cxpServerEnabled,
        port: settings.cxpServerPort,
      );
    });

/// Provider exposing the path of the CXP manifest directory.
///
/// Resolved once at startup; the resolved path is cached because
/// `getApplicationSupportDirectory()` is a platform-channel round-trip.
/// Tests override this provider to point at a temp directory.
final FutureProvider<String> cxpManifestDirectoryProvider =
    FutureProvider<String>((ref) async {
      return await const CxpPaths().manifestDirectory();
    });

/// Provider exposing the [LintCruxCxpRequestHandler] used by the
/// receive-side dispatch loop. Reads the violation store, table
/// state, and editor service via thunks so it always sees the live
/// values when a message arrives — see the handler docs for why this
/// matters.
///
/// The violation store and table state are PER-TAB providers. The CXP
/// server is root-hosted (one socket per app), so each thunk resolves
/// the ACTIVE tab's container through [activeTabContainerHandleProvider]
/// at dispatch time — an inbound cross-probe must search the tab the
/// user is looking at, not the empty root-scope store. The root `ref`
/// read is the empty-workspace fallback only.
final Provider<LintCruxCxpRequestHandler> cxpRequestHandlerProvider =
    Provider<LintCruxCxpRequestHandler>((ref) {
      final handle = ref.read(activeTabContainerHandleProvider);
      return LintCruxCxpRequestHandler(
        violationStore: () =>
            handle.activeContainer?.read(violationStoreProvider) ??
            ref.read(violationStoreProvider),
        tableState: () =>
            handle.activeContainer?.read(violationTableStateProvider) ??
            ref.read(violationTableStateProvider),
        openInEditor: (location) =>
            ref.read(clickToSourceServiceProvider).openInEditor(location),
        containment: ref.read(cxpPathContainmentProvider),
        // The `crux.design_id` fallback: resolve the design's `source`
        // artifact from the shared workspace and open it as a LintCrux
        // project via the WorkspaceRoot-published opener. Root-scoped: the
        // server socket is one-per-app and the opener acts on the
        // workspace, not a per-tab. It keeps the roots — nobody asked for
        // this design; a peer attached its id to a cross-probe.
        resolveAndOpenArtifact: (designId) async {
          final path = resolveLintcruxSourceArtifactPath(ref, designId);
          if (path == null) return false;
          // CXP §11's MUST: the artifact resolved through our OWN records
          // gets the same rule as a `file_path` on the wire, applied to the
          // value about to be opened. The sender chose the `design_id` that
          // selected this record, and the workspace directory is
          // user-writable, so "we resolved it ourselves" is not a
          // provenance.
          final outcome = await openCxpProject(
            ref,
            path,
            refuse: ref.read(cxpPathContainmentProvider).refuse,
          );
          return outcome.honored;
        },
        // `request_open_artifact`: the user asked for this project, so it
        // is held to the floor, not the roots (`kCxpOpenArtifactContainment`
        // says why). The record is read under the floor too, since the
        // rooted store drops one for a project never opened here, and the
        // request's hint is the fallback when nothing is recorded
        // (CXP §9.10).
        openRequestedArtifact: (designId, hintPath) async {
          final path =
              resolveOpenArtifactProjectPath(ref, designId) ?? hintPath;
          if (path == null) {
            return (
              honored: false,
              reason: 'No source artifact recorded for design "$designId".',
            );
          }
          return await openCxpProject(
            ref,
            path,
            refuse: kCxpOpenArtifactContainment.refuse,
          );
        },
      );
    });

/// Opens the LintCrux project at [path] for a CXP peer, under [refuse]: the
/// rule the route that reached here keeps — the floor for
/// `request_open_artifact`, the directories the user has opened for the
/// `crux.design_id` fallback. Returns whether it opened and, if not, why, in
/// words that never repeat the path (CXP §9.11).
///
/// A `<design>.crux-project` manifest is swapped for the lint project it
/// names *here*, and [refuse] judges the swapped path as well, so the string
/// checked is the string opened (CXP §11.3). `OpenProjectInWorkspace` swaps a
/// manifest itself; left to do it, it opened a path nothing had checked.
/// Handed a `.lintcrux` project, it has nothing to swap, so this refuses a
/// manifest that names another manifest rather than let the opener swap one
/// past the check.
///
/// The path must be a file here: a hint can name the sender's path on its
/// own machine layout, or a project since deleted. Checked only after
/// [refuse], so a malformed path is refused without this process ever
/// looking at it.
Future<CxpArtifactOpenOutcome> openCxpProject(
  Ref ref,
  String path, {
  required String? Function(String path) refuse,
}) async {
  final refusal = refuse(path);
  if (refusal != null) return (honored: false, reason: refusal);
  if (FileSystemEntity.typeSync(path) != FileSystemEntityType.file) {
    return (honored: false, reason: 'the artifact is not a file here');
  }
  final String project;
  switch (const CruxProjectResolver().resolve(path)) {
    case NotAManifest():
      project = path;
    case ManifestLintProject(:final lintProjectPath):
      project = lintProjectPath;
    case ManifestAmbiguous():
      return (
        honored: false,
        reason: 'the design directory holds more than one manifest',
      );
    case ManifestUnusable():
      return (
        honored: false,
        reason: 'the design manifest names no lint project LintCrux can open',
      );
  }
  if (project != path) {
    final swappedRefusal = refuse(project);
    if (swappedRefusal != null) return (honored: false, reason: swappedRefusal);
    if (CruxProjectParser.isManifestPath(project)) {
      return (
        honored: false,
        reason: 'the design manifest names another manifest',
      );
    }
  }
  final opened = await ref.read(cxpProjectOpenHandleProvider).open(project);
  return opened
      ? (honored: true, reason: null)
      : (honored: false, reason: 'LintCrux could not open the project');
}

/// Rolling buffer of cross-probe events the UI surface (Settings →
/// Remote Control and the cross-probe panel) renders. Capped at 50
/// entries — when full, the oldest entry is dropped.
class CxpEventLog {
  /// Creates an event log.
  const CxpEventLog({this.entries = const <CxpEventEntry>[]});

  /// Empty log.
  static const CxpEventLog empty = CxpEventLog();

  /// Maximum number of entries retained.
  static const int maxEntries = 50;

  /// The entries, oldest first.
  final List<CxpEventEntry> entries;

  /// Appends [entry], dropping the oldest if the buffer is full.
  CxpEventLog append(CxpEventEntry entry) {
    final next = List<CxpEventEntry>.from(entries)..add(entry);
    if (next.length > maxEntries) {
      next.removeRange(0, next.length - maxEntries);
    }
    return CxpEventLog(entries: List<CxpEventEntry>.unmodifiable(next));
  }
}

/// A single CXP event entry — peer join / leave or one inbound request.
class CxpEventEntry {
  /// Creates an event entry.
  const CxpEventEntry({
    required this.timestamp,
    required this.kind,
    required this.summary,
    this.peerId,
  });

  /// When the event was observed.
  final DateTime timestamp;

  /// Discriminator (peer presence / inbound message / outbound ack).
  final CxpEventKind kind;

  /// Short human-readable summary. ARB-friendly; the UI renders this
  /// verbatim.
  final String summary;

  /// Originating peer ID when applicable.
  final String? peerId;
}

/// Kind discriminator for [CxpEventEntry].
enum CxpEventKind {
  /// A peer connected.
  peerConnected,

  /// A peer disconnected.
  peerDisconnected,

  /// An inbound CXP request was received and dispatched.
  inboundRequest,

  /// A reply (ack or error) was sent back to a peer.
  outboundAck,

  /// A peer manifest appeared in the discovery directory.
  peerDiscovered,

  /// A peer manifest vanished from the discovery directory.
  peerLost,
}

/// Notifier maintaining the [CxpEventLog]. The lifecycle provider feeds
/// it from inbound dispatch and peer-presence events.
class CxpEventLogNotifier extends Notifier<CxpEventLog> {
  @override
  CxpEventLog build() => CxpEventLog.empty;

  /// Appends [entry] to the log.
  void append(CxpEventEntry entry) {
    state = state.append(entry);
  }

  /// Clears the log.
  void clear() {
    state = CxpEventLog.empty;
  }
}

/// Provider exposing the rolling event log for the cross-probe panel.
final NotifierProvider<CxpEventLogNotifier, CxpEventLog> cxpEventLogProvider =
    NotifierProvider<CxpEventLogNotifier, CxpEventLog>(
      CxpEventLogNotifier.new,
    );

/// Discovered peers (read-only snapshot). Refreshed on every
/// [CxpDiscoveryEvent].
class CxpPeersNotifier extends Notifier<List<CxpPeerManifest>> {
  @override
  List<CxpPeerManifest> build() => const <CxpPeerManifest>[];

  /// Replaces the snapshot.
  void replace(List<CxpPeerManifest> next) {
    state = List<CxpPeerManifest>.unmodifiable(next);
  }
}

/// Provider exposing the currently-known peers.
final NotifierProvider<CxpPeersNotifier, List<CxpPeerManifest>>
cxpPeersProvider = NotifierProvider<CxpPeersNotifier, List<CxpPeerManifest>>(
  CxpPeersNotifier.new,
);

/// Discovered-but-unreachable peers (read-only snapshot). Each entry is a
/// peer whose discovery manifest the connector found but whose CXP server
/// it could not dial.
///
/// This is the product-facing surface for [CxpPeerConnector.dialFailures],
/// which is otherwise consumed nowhere and leaves one-way connectivity
/// invisible — an unreachable peer looks identical to an absent one. The
/// cross-probe panel `watch`es this and renders a persistent warning row
/// per entry. Fed by [CxpServerLifecycle], which refreshes the snapshot
/// from the connector's `lastDialFailures` map on every signal that can
/// change it: a fresh dial failure (`dialFailures`), a peer connecting
/// (`server.presence` — a now-reachable peer is pruned), and a discovery
/// add/remove (a removed manifest drops its failure entry).
class CxpDialFailuresNotifier extends Notifier<List<CxpDialFailure>> {
  @override
  List<CxpDialFailure> build() => const <CxpDialFailure>[];

  /// Replaces the snapshot.
  void replace(List<CxpDialFailure> next) {
    state = List<CxpDialFailure>.unmodifiable(next);
  }
}

/// Provider exposing the discovered-but-unreachable peers.
final NotifierProvider<CxpDialFailuresNotifier, List<CxpDialFailure>>
cxpDialFailuresProvider =
    NotifierProvider<CxpDialFailuresNotifier, List<CxpDialFailure>>(
      CxpDialFailuresNotifier.new,
    );

/// State exposed by [cxpServerLifecycleProvider].
class CxpServerLifecycleState {
  /// Creates a lifecycle state.
  const CxpServerLifecycleState({
    required this.running,
    required this.boundPort,
    this.peerId,
    this.error,
  });

  /// Whether the server is currently running. `true` only after the
  /// underlying [LocalCxpServer.start] returned successfully.
  final bool running;

  /// Port the server is bound to. Equal to the configured port when
  /// [running] is `true`; `null` otherwise.
  final int? boundPort;

  /// Our peer ID (matches the value written into the discovery
  /// manifest). Null before first start.
  final String? peerId;

  /// Most recent start-up error, if any. Cleared on the next
  /// successful start.
  final String? error;
}

/// Async lifecycle owner for the LintCrux CXP server, manifest writer,
/// discovery watcher, and inbound dispatcher.
///
/// Watches `cxpServerConfigProvider` so toggling the server in
/// Settings → Remote Control or changing the port restarts the server
/// without rebooting the app. Disposes everything on
/// `ref.onDispose` so the manifest is removed and the socket is
/// released when the app shuts down.
class CxpServerLifecycle extends AsyncNotifier<CxpServerLifecycleState> {
  LintCruxCxpServer? _server;

  /// The services-layer handle to publish the running server into.
  /// Captured in [build] (while `ref` is valid) so [_teardown] can clear
  /// it without touching `ref` during disposal.
  CxpServerHandle? _handle;
  CxpManifestWriter? _manifestWriter;
  CxpDiscovery? _discovery;
  CxpPeerConnector? _connector;
  StreamSubscription<PeerPresenceEvent>? _presenceSub;
  StreamSubscription<CxpDiscoveryEvent>? _discoverySub;
  StreamSubscription<CxpDialFailure>? _dialFailuresSub;

  @override
  Future<CxpServerLifecycleState> build() async {
    _handle = ref.read(cxpServerHandleProvider);
    final config = ref.watch(cxpServerConfigProvider);
    final manifestDir = await ref.watch(cxpManifestDirectoryProvider.future);

    ref.onDispose(_teardown);

    await _teardown();

    // Reset the unreachable-peer snapshot on every (re)build so a disabled
    // server, a port change, or a restart never leaves stale warning rows in
    // the cross-probe panel. Re-populated below once the connector runs.
    final dialFailuresNotifier = ref.read(cxpDialFailuresProvider.notifier)
      ..replace(const <CxpDialFailure>[]);
    // The same for the peer list: discovery stopped in [_teardown], so the
    // last snapshot is stale. Left alone, a disabled server keeps showing
    // the peers it saw while running (the toolbar badge among them).
    ref.read(cxpPeersProvider.notifier).replace(const <CxpPeerManifest>[]);

    if (!config.enabled) {
      return const CxpServerLifecycleState(running: false, boundPort: null);
    }

    final peerId = LintCruxCxpServer.makePeerId(
      pid: pid,
      startedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );

    final handler = ref.read(cxpRequestHandlerProvider);
    final eventLog = ref.read(cxpEventLogProvider.notifier);

    final server = LintCruxCxpServer(
      peerId: peerId,
      port: config.port,
      // The floor, not the directories the user has opened. `LocalCxpServer`
      // holds one rule for both requests it screens, and a rooted one strips
      // the path hint from a `request_open_artifact` for a project LintCrux
      // has never opened — the very request that route exists to honour. A
      // `request_open_source` keeps its roots: the request handler applies
      // the rooted rule to the path it is about to hand an editor.
      containment: kCxpOpenArtifactContainment,
      onInbound: (inbound) async {
        eventLog.append(
          CxpEventEntry(
            timestamp: DateTime.now(),
            kind: CxpEventKind.inboundRequest,
            summary: '${inbound.message.kind} from ${inbound.from.peerId}',
            peerId: inbound.from.peerId,
          ),
        );
        final result = await handler.dispatch(inbound);
        // Apply state mutations the handler computed — against the
        // ACTIVE tab's per-tab providers (the same scope the handler's
        // thunks read from), falling back to root only when no tab is
        // active. Mutating the root-scope notifiers instead would leave
        // the visible table untouched.
        final tabContainer = ref
            .read(activeTabContainerHandleProvider)
            .activeContainer;
        final newTable = result.tableState;
        if (newTable != null) {
          (tabContainer == null
                  ? ref.read(violationTableStateProvider.notifier)
                  : tabContainer.read(violationTableStateProvider.notifier))
              .applyFromState(newTable);
        }
        final newSelection = result.selection;
        if (newSelection != null) {
          (tabContainer == null
                  ? ref.read(selectedViolationProvider.notifier)
                  : tabContainer.read(selectedViolationProvider.notifier))
              .select(newSelection);
        }
        // An actionable inbound message was applied (a highlight
        // landed, a source opened in the editor, or a design project opened)
        // — nudge the OS's attention affordance without stealing focus.
        // Gated by the user setting via the swappable `windowAttentionRequester`
        // seam (see `cxpAttentionGateProvider`), so this is a no-op when the
        // preference is off, and a safe no-op under tests.
        final honored = _ackHonored(result.ack);
        // `cxp.crossprobe` — the suite network-effect funnel. Recorded
        // once per inbound request with the ack's own honored bit, so a probe
        // LintCrux could not act on (unknown rule, no matching project) is
        // visible as a *declined* probe rather than as no probe at all: "the
        // funnel is working" and "the funnel is being tried and failing" are
        // the two answers this counter has to be able to tell apart. Neither
        // the peer id nor the element path is sent.
        ref
            .read(telemetryServiceProvider)
            .record(
              TelemetryEvent(
                'cxp.crossprobe',
                properties: <String, Object?>{
                  'direction': 'inbound',
                  'honored': honored,
                },
              ),
            );
        if (honored) unawaited(requestUserAttention());
        // Send the ack back to the originator.
        _server?.sendTo(inbound.from.peerId, result.ack);
        eventLog.append(
          CxpEventEntry(
            timestamp: DateTime.now(),
            kind: CxpEventKind.outboundAck,
            summary: '${result.ack.kind} → ${inbound.from.peerId}',
            peerId: inbound.from.peerId,
          ),
        );
      },
    );

    try {
      await server.start();
    } on SocketException catch (e) {
      return CxpServerLifecycleState(
        running: false,
        boundPort: null,
        peerId: peerId,
        error:
            'Failed to bind CXP server on port ${config.port}: '
            '${e.message}',
      );
    }
    _server = server;
    // Publish the running server to the services-layer handle so
    // services-layer originators (e.g. the Pro cross-probe originator)
    // can dispatch outbound messages without importing this feature
    // provider (ARCHITECTURE.md §6.2).
    _handle?.server = server;

    // Wire presence events into the rolling log so the cross-probe
    // panel can render "WaveCrux 0.7.0 connected" entries.
    _presenceSub = server.presence.listen((event) {
      eventLog.append(
        CxpEventEntry(
          timestamp: DateTime.now(),
          kind: event.connected
              ? CxpEventKind.peerConnected
              : CxpEventKind.peerDisconnected,
          summary: '${event.peer.productName} ${event.peer.productVersion}',
          peerId: event.peer.peerId,
        ),
      );
      // A peer connecting means the connector's handshake with it succeeded,
      // so it is pruned from `lastDialFailures` — refresh to drop its
      // warning row.
      _refreshDialFailures(dialFailuresNotifier);
    });

    // Publish our manifest so peers can discover us.
    final boundPort = server.boundPort ?? config.port;
    final manifestWriter = CxpManifestWriter(manifestDirectory: manifestDir);
    await manifestWriter.write(
      identity: server.selfIdentity,
      host: '127.0.0.1',
      port: boundPort,
    );
    _manifestWriter = manifestWriter;

    // Watch for peers appearing in the manifest directory. The directory
    // is suite-shared, so the raw scan always contains LintCrux's OWN
    // manifest — filter it or the cross-probe panel lists this very
    // process as a peer.
    final discovery = CxpDiscovery(manifestDirectory: manifestDir);
    await discovery.start();
    final selfPeerId = server.selfIdentity.peerId;
    List<CxpPeerManifest> foreignPeers() => [
      for (final m in discovery.peers)
        if (m.identity.peerId != selfPeerId) m,
    ];
    final peersNotifier = ref.read(cxpPeersProvider.notifier)
      ..replace(foreignPeers());
    _discoverySub = discovery.events.listen((event) {
      if (event.manifest.identity.peerId == selfPeerId) return;
      peersNotifier.replace(foreignPeers());
      // A removed manifest drops its entry from `lastDialFailures`; refresh
      // so a peer that quit stops being reported as unreachable.
      _refreshDialFailures(dialFailuresNotifier);
      eventLog.append(
        CxpEventEntry(
          timestamp: DateTime.now(),
          kind: event.added
              ? CxpEventKind.peerDiscovered
              : CxpEventKind.peerLost,
          summary:
              '${event.manifest.identity.productName} '
              '${event.manifest.identity.productVersion} '
              '(${event.manifest.host}:${event.manifest.port})',
          peerId: event.manifest.identity.peerId,
        ),
      );
    });
    _discovery = discovery;

    // Dial every discovered non-self peer so its server sees an inbound
    // Hello (its symmetric connector dials us back, filling OUR
    // connectedPeers). Passing `server:` additionally merges each link's
    // inbound frames into this server's dispatch stream and registers the
    // link as a reply route (`CxpServer.attachLinkedPeer`), so a peer we
    // merely dialed — and who never dials us back — can still reach our
    // request handler and get an ack back. Without `server:` the connector
    // proves presence only: link traffic lands on its own client socket
    // and nobody listens to it, so connector-link inbound is dropped.
    //
    // `subscriptions:` is narrowed to the request kinds LintCrux honours.
    // The default (`cxpSubscribeToAll`) subscribes to `notify_selection`
    // too, which would make every peer forward its selection gossip here;
    // the receive handler answers each one with `ErrorResponse(unsupported)`.
    // LintCrux consumes no gossip, so it announces only the kinds it acts
    // on and that traffic never reaches the wire.
    _connector = CxpPeerConnector(
      selfIdentity: server.selfIdentity,
      discovery: discovery,
      server: server.server,
      subscriptions: lintCruxCxpSubscriptions,
    )..start();
    // Surface discovered-but-unreachable peers. Each dial failure refreshes
    // the snapshot from the connector's per-peer `lastDialFailures` map (the
    // presence/discovery listeners above prune it as peers become reachable
    // or vanish), so the cross-probe panel can render a persistent warning
    // row instead of leaving one-way connectivity invisible.
    _dialFailuresSub = _connector!.dialFailures.listen(
      (_) => _refreshDialFailures(dialFailuresNotifier),
    );

    return CxpServerLifecycleState(
      running: true,
      boundPort: boundPort,
      peerId: peerId,
    );
  }

  /// Pushes the connector's current per-peer unreachable set into
  /// [notifier]. Reads `lastDialFailures` fresh (rather than accumulating
  /// stream events) so the snapshot reflects the connector's own pruning of
  /// peers that became reachable or whose manifest was removed. Safe to call
  /// after the connector is gone — it degrades to an empty list.
  void _refreshDialFailures(CxpDialFailuresNotifier notifier) {
    notifier.replace(
      _connector?.lastDialFailures.values.toList(growable: false) ??
          const <CxpDialFailure>[],
    );
  }

  Future<void> _teardown() async {
    await _presenceSub?.cancel();
    _presenceSub = null;
    await _discoverySub?.cancel();
    _discoverySub = null;
    await _dialFailuresSub?.cancel();
    _dialFailuresSub = null;
    await _connector?.stop();
    _connector = null;
    await _discovery?.stop();
    _discovery = null;
    await _manifestWriter?.remove();
    _manifestWriter = null;
    final server = _server;
    _server = null;
    // Clear the services-layer handle so originators see "no server".
    // Uses the handle captured in `build` — `ref` is invalid here.
    _handle?.server = null;
    await server?.stop();
  }

  /// Broadcasts [message] to every connected peer that subscribed to
  /// its kind. No-op when the server is not running.
  ///
  /// Used by the Pro overlay's NotifySelection emitter. Lives on the notifier
  /// rather than the state class so callers don't need to wrap the call in an
  /// `AsyncValue.when`.
  void broadcast(CxpMessage message) => _server?.broadcast(message);

  /// Sends [message] to a single connected peer identified by
  /// [peerId]. Returns `true` when the message reached the peer's
  /// outbound socket; `false` when the peer is not connected, the
  /// server is not running, or its `sendTo` rejected the message
  /// (e.g. the peer never advertised the message's kind).
  ///
  /// Used by the Pro overlay's targeted cross-probe origination
  /// — the "Cross-probe to peer →" menu's per-peer
  /// dispatch helpers (`originateToNetCrux`, `originateToWaveCrux`)
  /// call this to send `request_highlight` and the companion
  /// `notify_selection` payload to one specific peer rather than
  /// broadcasting to every subscriber.
  bool sendTo(String peerId, CxpMessage message) =>
      _server?.sendTo(peerId, message) ?? false;

  /// Sends an ack-bearing [request] to [peerId] and returns whether it was
  /// delivered plus the peer's [RequestHighlightAck] (null on timeout /
  /// unreachable). The cross-probe panel's per-peer send uses this so a
  /// rejected send can be surfaced as a toast rather than silently dropped.
  Future<({bool delivered, RequestHighlightAck? ack})> requestHighlight(
    String peerId,
    RequestHighlight request,
  ) async =>
      await _server?.requestHighlight(peerId, request) ??
      (delivered: false, ack: null);
}

/// Provider exposing the [CxpServerLifecycle].
final AsyncNotifierProvider<CxpServerLifecycle, CxpServerLifecycleState>
cxpServerLifecycleProvider =
    AsyncNotifierProvider<CxpServerLifecycle, CxpServerLifecycleState>(
      CxpServerLifecycle.new,
    );

/// Whether an inbound-dispatch [ack] represents an actionable message that was
/// honored — the signal the attention gate uses to decide whether to request
/// the OS's attention. Covers every ack type LintCrux can reply with; a plain
/// `ErrorResponse` (unsupported kind) is never actionable.
bool _ackHonored(CxpMessage ack) =>
    (ack is RequestHighlightAck && ack.honored) ||
    (ack is RequestOpenSourceAck && ack.honored) ||
    (ack is RequestOpenArtifactAck && ack.honored);

/// Attention gate — swaps the global `windowAttentionRequester` backend
/// based on the [AppSettings.requestAttentionOnCrossProbe] setting.
///
/// Swaps to the no-op backend when the preference is off and back to the
/// method-channel backend (dock bounce / taskbar flash / Wayland urgency) when
/// on. Realized for the whole app session by the app shell's eager `watch`, so
/// the `ref.listen` stays installed; `fireImmediately` applies the persisted
/// value at boot. Mirrors WaveCrux's `CxpLifecycleBridge` attention gate,
/// adapted to LintCrux's synchronous `appSettingsProvider`.
final Provider<void> cxpAttentionGateProvider = Provider<void>((ref) {
  ref.listen<AppSettings>(
    appSettingsProvider,
    (previous, next) {
      windowAttentionRequester = next.requestAttentionOnCrossProbe
          ? const MethodChannelWindowAttentionRequester()
          : const NoopWindowAttentionRequester();
    },
    fireImmediately: true,
  );
});
