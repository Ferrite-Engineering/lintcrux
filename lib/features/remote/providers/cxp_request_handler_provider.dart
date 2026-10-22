// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:crux_project/crux_project.dart' show CruxProjectParser;
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/workspace/services/crux_project_resolution.dart';
import 'package:lintcrux/services/editor/editor_command_provider.dart';
import 'package:lintcrux/services/remote/cxp/cxp_project_open_handle.dart';
import 'package:lintcrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:lintcrux/services/remote/cxp/lintcrux_cxp_request_handler.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';
import 'package:lintcrux/services/workspace/active_tab_container_handle.dart';

/// Provider exposing the [LintCruxCxpRequestHandler] the shared CXP runtime's
/// handler ([LintCruxCxpWrappedHandler]) dispatches to. Reads the violation
/// store, table state, and editor service via thunks so it always sees the
/// live values when a message arrives — see the handler docs for why this
/// matters.
///
/// The violation store and table state are PER-TAB providers. The CXP
/// runtime is root-hosted (one socket per app), so each thunk resolves
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
          final path = await resolveLintcruxSourceArtifactPath(ref, designId);
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
              await resolveOpenArtifactProjectPath(ref, designId) ?? hintPath;
          if (path == null) {
            return (
              honored: false,
              reason: 'No source artifact recorded for that design.',
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

/// What the shared CXP runtime calls when a peer sends LintCrux a request.
///
/// A thin wrapper over [LintCruxCxpRequestHandler.dispatch]: it applies the
/// table filter and selection that dispatch computed to the ACTIVE tab (the
/// same scope the handler's thunks read from; mutating the root-scope
/// notifiers instead would leave the visible table untouched), records the
/// inbound `cxp.crossprobe` event, and returns the outcome for the runtime to
/// acknowledge. It never replies on the wire and never asks for attention: the
/// runtime does both for a request that was honoured.
class LintCruxCxpWrappedHandler extends CruxCxpRequestHandler {
  /// Creates a handler reading providers through [_ref].
  LintCruxCxpWrappedHandler(this._ref);

  final Ref _ref;

  @override
  Future<CruxCxpHandlerResult> highlight(
    RequestHighlight request,
    PeerIdentity from,
  ) => _run(request, from);

  @override
  Future<CruxCxpHandlerResult> openSource(
    RequestOpenSource request,
    PeerIdentity from,
  ) => _run(request, from);

  @override
  Future<CruxCxpHandlerResult> openArtifact(
    RequestOpenArtifact request,
    PeerIdentity from,
  ) => _run(request, from);

  Future<CruxCxpHandlerResult> _run(
    CxpMessage message,
    PeerIdentity from,
  ) async {
    final dispatched = await _ref
        .read(cxpRequestHandlerProvider)
        .dispatch(
          InboundCxpMessage(
            envelope: CxpEnvelope(
              messageId: '',
              from: from.peerId,
              kind: message.kind,
              payload: const <String, Object?>{},
            ),
            message: message,
            from: from,
          ),
        );
    final tabContainer = _ref
        .read(activeTabContainerHandleProvider)
        .activeContainer;
    final newTable = dispatched.tableState;
    if (newTable != null) {
      (tabContainer == null
              ? _ref.read(violationTableStateProvider.notifier)
              : tabContainer.read(violationTableStateProvider.notifier))
          .applyFromState(newTable);
    }
    final newSelection = dispatched.selection;
    if (newSelection != null) {
      (tabContainer == null
              ? _ref.read(selectedViolationProvider.notifier)
              : tabContainer.read(selectedViolationProvider.notifier))
          .select(newSelection);
    }
    final result = _resultOf(dispatched.ack);
    // `cxp.crossprobe` — the suite network-effect funnel. Recorded once per
    // inbound request with the ack's own honored bit, so a probe LintCrux
    // could not act on (unknown rule, no matching project) is visible as a
    // *declined* probe rather than as no probe at all: "the funnel is
    // working" and "the funnel is being tried and failing" are the two
    // answers this counter has to be able to tell apart. Neither the peer id
    // nor the element path is sent.
    _ref
        .read(telemetryServiceProvider)
        .record(
          TelemetryEvent(
            'cxp.crossprobe',
            properties: <String, Object?>{
              'direction': 'inbound',
              'honored': result.honored,
            },
          ),
        );
    return result;
  }

  /// The runtime's view of the acknowledgement [ack] the dispatcher computed.
  static CruxCxpHandlerResult _resultOf(CxpMessage? ack) => switch (ack) {
    RequestHighlightAck(:final honored, :final reason) => CruxCxpHandlerResult(
      honored: honored,
      reason: reason,
    ),
    RequestOpenSourceAck(:final honored, :final reason) => CruxCxpHandlerResult(
      honored: honored,
      reason: reason,
    ),
    RequestOpenArtifactAck(:final honored, :final reason) =>
      CruxCxpHandlerResult(honored: honored, reason: reason),
    _ => CruxCxpHandlerResult.unsupported,
  };
}

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
