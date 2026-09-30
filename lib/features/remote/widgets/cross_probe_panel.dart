// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart' as cxp_ui;
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/features/remote/providers/cross_probe_originate_gate_provider.dart';
import 'package:lintcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:lintcrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:lintcrux/services/remote/cxp/lintcrux_name_resolver.dart';
import 'package:lintcrux/services/workspace/active_tab_container_handle.dart';

/// LintCrux's docked cross-probe panel.
///
/// A thin `ConsumerStatefulWidget` host around the shared
/// `crux_cxp_ui.CrossProbePanel`: it owns a [LintCruxCrossProbePanelController]
/// that bridges LintCrux's live CXP Riverpod state into the panel's reactive
/// contract, and disposes it with the widget. LintCrux's old modal `Dialog`
/// presentation of the panel is retired in favour of this docked side-panel,
/// which `ViewerScaffold` swaps into a right-hand slot when
/// `PanelLayoutState.crossProbeVisible` is set.
///
/// Named distinctly from the shared `CrossProbePanel` widget it wraps (the
/// import is prefixed `cxp_ui`) to avoid the name collision.
class LintCruxCrossProbePanel extends ConsumerStatefulWidget {
  /// Creates the docked cross-probe panel.
  const LintCruxCrossProbePanel({super.key});

  @override
  ConsumerState<LintCruxCrossProbePanel> createState() =>
      _LintCruxCrossProbePanelState();
}

class _LintCruxCrossProbePanelState
    extends ConsumerState<LintCruxCrossProbePanel> {
  late final LintCruxCrossProbePanelController _controller;

  @override
  void initState() {
    super.initState();
    _controller = LintCruxCrossProbePanelController(ref);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return cxp_ui.CrossProbePanel(
      controller: _controller,
      // Docked as a CruxDock tab: the strip already carries the icon, the
      // label and the ×, so the panel's own header would duplicate all
      // three directly underneath.
      showHeader: false,
      strings: cxp_ui.CrossProbePanelStrings(
        title: l10n.crossProbePanelTitle,
        closeTooltip: l10n.crossProbePanelClose,
        serverOffline: l10n.crossProbePanelServerStopped,
        peersSectionTitle: l10n.crossProbePanelPeersHeader,
        noPeers: l10n.crossProbePanelPeersEmpty,
        sendTooltip: l10n.crossProbeSendTooltip,
        unreachableSectionTitle: l10n.crossProbeUnreachableTitle,
        eventsSectionTitle: l10n.crossProbePanelEventsHeader,
        noEvents: l10n.crossProbePanelEventsEmpty,
        clearEventsLabel: l10n.crossProbePanelClearEvents,
        // The peer's reason arrives in the peer's own words; only the frame
        // around it is ours to translate.
        sendRejected: (peer, reason) => reason == null || reason.isEmpty
            ? l10n.crossProbeSendFailed(peer)
            : l10n.crossProbeSendRefused(peer, reason),
      ),
    );
  }
}

/// Adapts LintCrux's live CXP Riverpod state onto the app-agnostic
/// [cxp_ui.CrossProbePanelController] the shared panel renders against.
///
/// Bridges four reactive sources into the four [ValueListenable]s the panel
/// wraps in `ValueListenableBuilder`s — `cxpPeersProvider` (mapped from
/// LintCrux's discovered [CxpPeerManifest]s onto their [PeerIdentity]),
/// `cxpEventLogProvider` (mapped from [CxpEventEntry] into the shared
/// [cxp_ui.CrossProbeEvent] superset), `cxpDialFailuresProvider`, and
/// `cxpServerLifecycleProvider`'s `running` flag — via
/// `ref.listenManual(..., fireImmediately: true)`, and routes the panel's
/// commands back into LintCrux:
///
/// * [onSendTo] resolves the active tab's selected violation and sends a
///   `notify_selection` (a `rule` element) to the chosen peer, tagging it with
///   the `crux.design_id` metadata so a receiver with none of this design open
///   can resolve and open it.
/// * [onClose] / [onOpenPanel] toggle the `crossProbeVisible` flag.
/// * [onClearEvents] empties LintCrux's event buffer.
class LintCruxCrossProbePanelController
    implements cxp_ui.CrossProbePanelController {
  /// Creates a controller bound to [_ref] (the host widget's `ref`). Wires the
  /// reactive bridges immediately.
  LintCruxCrossProbePanelController(this._ref) {
    _peersSub = _ref.listenManual<List<CxpPeerManifest>>(
      cxpPeersProvider,
      (_, next) =>
          _peers.value = next.map((m) => m.identity).toList(growable: false),
      fireImmediately: true,
    );
    _unreachableSub = _ref.listenManual<List<CxpDialFailure>>(
      cxpDialFailuresProvider,
      (_, next) => _unreachable.value = next,
      fireImmediately: true,
    );
    _runningSub = _ref.listenManual<AsyncValue<CxpServerLifecycleState>>(
      cxpServerLifecycleProvider,
      (_, next) => _serverRunning.value = next.value?.running ?? false,
      fireImmediately: true,
    );
    _eventsSub = _ref.listenManual<CxpEventLog>(
      cxpEventLogProvider,
      (_, next) => _events.value = next.entries.map(_toSharedEvent).toList(),
      fireImmediately: true,
    );
  }

  final WidgetRef _ref;

  final ValueNotifier<List<PeerIdentity>> _peers =
      ValueNotifier<List<PeerIdentity>>(const <PeerIdentity>[]);
  final ValueNotifier<List<cxp_ui.CrossProbeEvent>> _events =
      ValueNotifier<List<cxp_ui.CrossProbeEvent>>(
        const <cxp_ui.CrossProbeEvent>[],
      );
  final ValueNotifier<List<CxpDialFailure>> _unreachable =
      ValueNotifier<List<CxpDialFailure>>(const <CxpDialFailure>[]);
  final ValueNotifier<bool> _serverRunning = ValueNotifier<bool>(false);

  ProviderSubscription<List<CxpPeerManifest>>? _peersSub;
  ProviderSubscription<CxpEventLog>? _eventsSub;
  ProviderSubscription<List<CxpDialFailure>>? _unreachableSub;
  ProviderSubscription<AsyncValue<CxpServerLifecycleState>>? _runningSub;

  @override
  ValueListenable<List<PeerIdentity>> get peers => _peers;

  @override
  ValueListenable<List<cxp_ui.CrossProbeEvent>> get events => _events;

  @override
  ValueListenable<List<CxpDialFailure>> get unreachable => _unreachable;

  @override
  ValueListenable<bool> get serverRunning => _serverRunning;

  @override
  ValueListenable<cxp_ui.CrossProbeSendFailure?> get sendFailure =>
      _sendFailure;

  final ValueNotifier<cxp_ui.CrossProbeSendFailure?> _sendFailure =
      ValueNotifier<cxp_ui.CrossProbeSendFailure?>(null);

  @override
  void onSendTo(PeerIdentity peer) => unawaited(_sendTo(peer));

  /// Resolves the active tab's selected violation and sends it to [peer] as an
  /// ack-bearing `request_highlight` — which the LintCrux inbound handler
  /// already acts on (select the violation row) and acks — then surfaces a
  /// rejected or undelivered send as a panel toast (a send is never a silent
  /// no-op). The Pro selection emitter still broadcasts fire-and-forget
  /// `notify_selection`.
  ///
  /// Origination is a Pro capability, and this button is a route to it that
  /// ships in open core — so the tier is checked HERE, first, before the
  /// selection is even resolved. A denied press has already been explained by
  /// the gate; an unselected row after an admitted press is the existing
  /// quiet no-op, which is a different situation from a refusal.
  Future<void> _sendTo(PeerIdentity peer) async {
    if (!_ref.read(crossProbeOriginateGateProvider)(_ref.context)) return;
    // The selection + project are per-tab; resolve the ACTIVE tab's container
    // (the panel is app-level, so its own `ref` is root). Fall back to root
    // when no tab is active (an unlikely case that simply has no selection).
    final container = _ref
        .read(activeTabContainerHandleProvider)
        .activeContainer;
    final violation = container == null
        ? _ref.read(selectedViolationProvider)
        : container.read(selectedViolationProvider);
    if (violation == null) return;
    final rulePath = LintCruxNameResolver.encodeViolationAsRulePath(violation);
    if (rulePath == null) return;
    final project = container == null
        ? _ref.read(currentProjectProvider)
        : container.read(currentProjectProvider);
    final designId = project == null ? null : cxpLintcruxDesignId(project);
    // Read before the ack wait: the probe is counted whether or not the panel
    // is still open when the ack lands.
    final telemetry = _ref.read(telemetryServiceProvider);
    final result = await _ref
        .read(cxpServerLifecycleProvider.notifier)
        .requestHighlight(
          peer.peerId,
          RequestHighlight(
            element: ElementId(kind: ElementKind.rule, path: rulePath),
            metadata: <String, Object?>{
              'lintcrux.violation_severity': violation.severity.name,
              cxpDesignIdMetadataKey: ?designId,
            },
          ),
        );
    final ack = result.ack;
    if (result.delivered) {
      // The outbound half of the funnel — see the inbound emit in
      // `cxp_server_provider.dart` for why the honored bit is a property
      // rather than a filter. A probe that was never delivered is not
      // counted: nothing reached a peer, so there is no funnel step to
      // attribute it to.
      telemetry.record(
        TelemetryEvent(
          'cxp.crossprobe',
          properties: <String, Object?>{
            'direction': 'outbound',
            'honored': ack != null && ack.honored,
          },
        ),
      );
    }
    // The ack wait runs up to five seconds, and the panel can close inside
    // it. Past that point `_ref` belongs to a disposed widget and the
    // failure notifier is disposed, so both would throw.
    if (_disposed) return;
    final peerLabel = peer.productName.isEmpty ? peer.peerId : peer.productName;
    if (!result.delivered) {
      // The peer went away between the panel listing it and the send. A
      // send is never a silent no-op: the panel otherwise looks as if it
      // did nothing at all.
      _reportSendFailure(cxp_ui.CrossProbeSendFailure(peerLabel: peerLabel));
      return;
    }
    if (ack == null || !ack.honored) {
      _reportSendFailure(
        cxp_ui.CrossProbeSendFailure(peerLabel: peerLabel, reason: ack?.reason),
      );
    }
  }

  /// Publishes [failure] for the panel to toast. Failures compare by value,
  /// so one equal to the last would not notify the panel and a second failed
  /// send to the same peer would be silent; clearing first makes each count.
  void _reportSendFailure(cxp_ui.CrossProbeSendFailure failure) {
    _sendFailure
      ..value = null
      ..value = failure;
  }

  @override
  void onOpenPanel() => _ref
      .read(panelLayoutProvider.notifier)
      .setCrossProbeVisible(visible: true);

  @override
  void onClose() => _ref
      .read(panelLayoutProvider.notifier)
      .setCrossProbeVisible(visible: false);

  @override
  void onClearEvents() => _ref.read(cxpEventLogProvider.notifier).clear();

  /// Set by [dispose]. A send still awaiting its ack checks it before touching
  /// the widget's `ref` or the notifiers.
  bool _disposed = false;

  /// Releases the bridge subscriptions and backing notifiers.
  void dispose() {
    _disposed = true;
    _peersSub?.close();
    _eventsSub?.close();
    _unreachableSub?.close();
    _runningSub?.close();
    _peers.dispose();
    _events.dispose();
    _unreachable.dispose();
    _serverRunning.dispose();
    _sendFailure.dispose();
  }

  /// Maps a LintCrux [CxpEventEntry] onto the shared, richer
  /// [cxp_ui.CrossProbeEvent] — folding LintCrux's coarser event kind (plus
  /// the leading wire-kind token in the entry summary, for the inbound /
  /// outbound rows) into the panel's semantic categories.
  cxp_ui.CrossProbeEvent _toSharedEvent(CxpEventEntry e) {
    switch (e.kind) {
      case CxpEventKind.peerConnected:
        return cxp_ui.CrossProbeEvent.peerConnected(
          peerLabel: e.summary,
          timestamp: e.timestamp,
        );
      case CxpEventKind.peerDisconnected:
        return cxp_ui.CrossProbeEvent.peerDisconnected(
          peerLabel: e.summary,
          timestamp: e.timestamp,
        );
      case CxpEventKind.peerDiscovered:
        return cxp_ui.CrossProbeEvent(
          kind: cxp_ui.CrossProbeEventKind.other,
          peerLabel: e.summary,
          timestamp: e.timestamp,
          messageKind: 'peer discovered',
        );
      case CxpEventKind.peerLost:
        return cxp_ui.CrossProbeEvent(
          kind: cxp_ui.CrossProbeEventKind.other,
          peerLabel: e.summary,
          timestamp: e.timestamp,
          messageKind: 'peer lost',
        );
      case CxpEventKind.inboundRequest:
        final wireKind = _leadingToken(e.summary);
        final kind = switch (wireKind) {
          CxpMessageKind.requestHighlight =>
            cxp_ui.CrossProbeEventKind.highlightReceived,
          CxpMessageKind.notifySelection =>
            cxp_ui.CrossProbeEventKind.selectionReceived,
          CxpMessageKind.requestOpenArtifact =>
            cxp_ui.CrossProbeEventKind.openArtifact,
          _ => cxp_ui.CrossProbeEventKind.other,
        };
        return cxp_ui.CrossProbeEvent(
          kind: kind,
          direction: cxp_ui.CrossProbeEventDirection.inbound,
          peerLabel: e.peerId ?? e.summary,
          timestamp: e.timestamp,
          summary: e.summary,
          messageKind: wireKind,
        );
      case CxpEventKind.outboundAck:
        return cxp_ui.CrossProbeEvent(
          kind: cxp_ui.CrossProbeEventKind.other,
          direction: cxp_ui.CrossProbeEventDirection.outbound,
          peerLabel: e.peerId ?? e.summary,
          timestamp: e.timestamp,
          summary: e.summary,
          messageKind: _leadingToken(e.summary),
        );
    }
  }

  /// The first whitespace-delimited token of an event [summary] — the wire
  /// message-kind the lifecycle stamped in front of `' from '` / `' → '`.
  static String _leadingToken(String summary) => summary.split(' ').first;
}
