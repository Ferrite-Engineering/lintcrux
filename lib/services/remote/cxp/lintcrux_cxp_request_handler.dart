// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:lintcrux/domain/interfaces/violation_store.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';
import 'package:lintcrux/services/editor/click_to_source_service.dart';
import 'package:lintcrux/services/remote/cxp/lintcrux_name_resolver.dart';

/// Outcome of dispatching one inbound CXP message.
///
/// Carries the ack the receive-side handler computed so the lifecycle
/// layer can send it back to the originating peer (or, in tests, assert
/// against it). [tableState] / [selection] reflect the
/// post-dispatch state mutations the handler performed; both are
/// nullable so a no-op dispatch (e.g. an unsupported element kind) does
/// not require fabricating dummy state.
class CxpDispatchResult {
  /// Creates a dispatch result.
  const CxpDispatchResult({
    required this.ack,
    this.tableState,
    this.selection,
    this.openSourceResult,
  });

  /// The CxpMessage to send back to the originator. Always non-null —
  /// every inbound request gets an ack of some kind so the requester
  /// does not time out.
  final CxpMessage ack;

  /// Post-dispatch [ViolationTableState] (if the handler updated it).
  final ViolationTableState? tableState;

  /// Post-dispatch selected violation (if the handler updated it).
  final Violation? selection;

  /// Outcome of a [ClickToSourceService.openInEditor] call (if the
  /// handler invoked the editor). Useful for the cross-probe panel's
  /// event log and for integration tests that want to inspect the
  /// shelled-out command.
  final ClickToSourceResult? openSourceResult;
}

/// What opening the artifact a `request_open_artifact` named came to:
/// whether LintCrux opened it, and, when it did not, why — in words fit for
/// the ack's `reason`, which never repeat the path (CXP §9.11).
typedef CxpArtifactOpenOutcome = ({bool honored, String? reason});

/// Receive-side dispatcher for CXP messages targeting LintCrux.
///
/// One instance lives behind `cxpServerLifecycleProvider`. The
/// lifecycle wires the [LintCruxCxpServer.onInbound] callback to
/// [dispatch], applies the returned state to the table / selection
/// notifiers, and sends the ack back to the originator via
/// [LintCruxCxpServer.sendTo].
///
/// The handler is *pure* — it does not directly touch the violation
/// table notifier or the selection notifier. Returning the computed
/// state from each dispatch keeps the unit tests free of widget-tree
/// scaffolding and lets the lifecycle layer own all Riverpod
/// integration in one place.
class LintCruxCxpRequestHandler {
  /// Creates a handler.
  ///
  /// All four collaborators are passed as thunks so the handler always
  /// reads the *current* value at dispatch time rather than the value
  /// captured at construction. This matters because the lifecycle
  /// provider holds a single handler instance for the life of the
  /// server and the violation store / table state can change
  /// underneath it.
  LintCruxCxpRequestHandler({
    required this.violationStore,
    required this.tableState,
    required this.openInEditor,
    this.resolveAndOpenArtifact,
    this.openRequestedArtifact,
    CxpPathContainment? containment,
  }) : containment = containment ?? const CxpPathContainment();

  /// CXP §11's rule for a path about to become an editor argv — in
  /// production the rooted rule, the directories the user has opened.
  ///
  /// `LintCruxCxpServer` screens the wire with the floor only, because its
  /// one rule also screens a `request_open_artifact` hint, which must not be
  /// rooted; so this check is the one that keeps a `request_open_source` to
  /// the directories the user has opened. The default is the floor rule
  /// (absolute, well-formed), which is what the receive-side unit tests get
  /// without wiring a session.
  final CxpPathContainment containment;

  /// Read the live [ViolationStore] (typically
  /// `() => ref.read(violationStoreProvider)`).
  final ViolationStore Function() violationStore;

  /// Read the live [ViolationTableState] (typically
  /// `() => ref.read(violationTableStateProvider)`).
  final ViolationTableState Function() tableState;

  /// Open [SourceLocation] in the user's configured editor. Wired to
  /// `ClickToSourceService.openInEditor` in production and to a fake
  /// launcher in tests.
  final Future<ClickToSourceResult> Function(SourceLocation location)
  openInEditor;

  /// Resolve the shared-workspace `source` artifact for a `design_id` and open
  /// it as a LintCrux project, returning whether it opened.
  ///
  /// This is the `crux.design_id` fallback a highlight takes when it misses
  /// locally, and in production it keeps the roots: the id arrived attached
  /// to a cross-probe, and nobody asked LintCrux to open that design.
  ///
  /// Optional so the wide swath of receive-side unit tests that don't exercise
  /// the shared workspace need not supply it. When null (or when it returns
  /// `false`) the open-on-miss path degrades to a graceful not-honored ack
  /// rather than throwing. Wired in production to the services-layer
  /// `CxpProjectOpenHandle` + the workspace store.
  final Future<bool> Function(String designId)? resolveAndOpenArtifact;

  /// Open the project a `request_open_artifact` names — the shared-workspace
  /// `source` record for `designId`, else the request's `path` hint — and
  /// report whether it opened, and why not.
  ///
  /// A separate route from [resolveAndOpenArtifact] because it keeps a
  /// different rule: the user asked for this project (in VS Code, "Open in
  /// LintCrux Desktop"), so production holds it to the floor, not the
  /// directories the user has opened (`kCxpOpenArtifactContainment` says
  /// why). When null the request is declined gracefully. Wired in production
  /// in `cxp_server_provider.dart`.
  final Future<CxpArtifactOpenOutcome> Function(
    String designId,
    String? hintPath,
  )?
  openRequestedArtifact;

  /// Dispatches a single inbound message and returns the ack + any
  /// state mutations the receive-side handler decided to apply.
  ///
  /// Every inbound request the handler sees (after the server's
  /// internal Hello / Subscribe filter) needs a reply, even when
  /// LintCrux cannot honour it, because the originator times out
  /// otherwise. Kinds LintCrux implements get their *matching* ack type
  /// ([RequestHighlightAck] / [RequestOpenSourceAck]); kinds it does not
  /// implement get an [ErrorResponse] with
  /// [CxpErrorCode.unsupported]. Replying to an arbitrary kind with a
  /// `RequestHighlightAck` would be a wire-contract violation — the
  /// originator correlates on [CxpEnvelope.messageId] but still decodes
  /// by kind, and would see an ack for a request it never sent.
  Future<CxpDispatchResult> dispatch(InboundCxpMessage inbound) async {
    final message = inbound.message;
    final envelope = inbound.envelope;

    if (message is RequestHighlight) {
      return await _dispatchRequestHighlight(message, envelope.messageId);
    }
    if (message is RequestOpenSource) {
      return await _dispatchRequestOpenSource(message, envelope.messageId);
    }
    if (message is RequestOpenArtifact) {
      return await _dispatchRequestOpenArtifact(message, envelope.messageId);
    }
    // Anything else (e.g. a NotifySelection a peer addressed directly
    // rather than broadcasting) is a kind LintCrux does not act on. Reply
    // with an ErrorResponse rather than a fabricated RequestHighlightAck
    // so the originator can decode the reply against the request it
    // actually sent.
    return CxpDispatchResult(
      ack: ErrorResponse(
        code: CxpErrorCode.unsupported,
        message: 'LintCrux does not handle "${message.kind}" messages.',
        inReplyTo: envelope.messageId,
      ),
    );
  }

  Future<CxpDispatchResult> _dispatchRequestHighlight(
    RequestHighlight req,
    String requestId,
  ) async {
    final element = req.element;
    final store = violationStore();
    final base = tableState();

    switch (element.kind.known) {
      case KnownElementKind.rule:
        return await _withWorkspaceFallback(
          req,
          requestId,
          _highlightRule(req, requestId, store, base),
        );
      case KnownElementKind.source:
        return await _withWorkspaceFallback(
          req,
          requestId,
          _highlightSource(req, requestId, store, base),
        );
      case KnownElementKind.signal:
        return _filterByLocalPath(
          req,
          requestId,
          store,
          base,
          ruleSubstring: element.path,
        );
      case KnownElementKind.instance:
        return _filterByLocalPath(
          req,
          requestId,
          store,
          base,
          ruleSubstring: element.path,
        );
      case KnownElementKind.scope:
      case KnownElementKind.net:
      case KnownElementKind.port:
      case KnownElementKind.marker:
      case KnownElementKind.test:
      case KnownElementKind.breakpoint:
      // `ElementKind` is open: a peer on a newer protocol revision can
      // name a kind this build does not model. Decline it exactly like a
      // known-but-unrepresentable kind — a graceful `honored: false` ack
      // naming the wire string, never a throw. The originator learns the
      // request went unserved and moves on; an older LintCrux must not be
      // crashable by a newer peer's vocabulary.
      case null:
        return CxpDispatchResult(
          ack: RequestHighlightAck(
            inReplyTo: requestId,
            honored: false,
            reason:
                'LintCrux does not represent '
                '${element.kind.name} elements.',
          ),
        );
    }
  }

  /// Wraps a local highlight [local]: when it was honored, returns it
  /// unchanged; when it missed, falls back to the shared workspace. Reads
  /// `crux.design_id` from the request's [RequestHighlight.metadata] and, if a
  /// `source` artifact is recorded for that design, opens the design's LintCrux
  /// project via [resolveAndOpenArtifact].
  ///
  /// The re-highlight is deliberately *not* re-attempted after the open: a
  /// LintCrux project loads and lints asynchronously, so the matching
  /// violation is not in the store synchronously. Acking honored on the open
  /// alone is the right answer for a linter (LintCrux has no
  /// waveform-open re-apply path); the user lands on the design they were
  /// pointed at and the run populates the table as it completes.
  Future<CxpDispatchResult> _withWorkspaceFallback(
    RequestHighlight req,
    String requestId,
    CxpDispatchResult local,
  ) async {
    final ack = local.ack;
    if (ack is RequestHighlightAck && ack.honored) return local;
    final opener = resolveAndOpenArtifact;
    if (opener == null) return local;
    final designId = req.metadata[cxpDesignIdMetadataKey];
    if (designId is! String || designId.isEmpty) return local;
    final opened = await opener(designId);
    if (!opened) return local;
    return CxpDispatchResult(
      ack: RequestHighlightAck(
        inReplyTo: requestId,
        honored: true,
        reason: 'Opened the design project from the shared workspace.',
      ),
    );
  }

  /// Handles an inbound `request_open_artifact`: a peer names a shared
  /// design and the kind of artifact it wants opened. LintCrux opens only its
  /// own `source` (`.lintcrux` project) artifacts; [openRequestedArtifact]
  /// resolves the concrete file through the shared workspace store
  /// (preferring that over the sender's optional path hint, whose absolute
  /// path may not exist on this machine), checks it, and opens it. Acks
  /// honored=false with a reason — rather than silently dropping — when the
  /// kind isn't a source, nothing names a project, the path is refused, or
  /// the open fails.
  Future<CxpDispatchResult> _dispatchRequestOpenArtifact(
    RequestOpenArtifact req,
    String requestId,
  ) async {
    if (req.artifactKind != 'source') {
      return CxpDispatchResult(
        ack: RequestOpenArtifactAck(
          inReplyTo: requestId,
          honored: false,
          reason:
              'LintCrux opens only "source" artifacts, not '
              '"${req.artifactKind}".',
        ),
      );
    }
    final opener = openRequestedArtifact;
    if (opener == null) {
      return CxpDispatchResult(
        ack: RequestOpenArtifactAck(
          inReplyTo: requestId,
          honored: false,
          reason: 'No workspace is available to open the project into.',
        ),
      );
    }
    final outcome = await opener(req.designId, req.path);
    return CxpDispatchResult(
      ack: RequestOpenArtifactAck(
        inReplyTo: requestId,
        honored: outcome.honored,
        reason: outcome.honored ? null : outcome.reason,
      ),
    );
  }

  CxpDispatchResult _highlightRule(
    RequestHighlight req,
    String requestId,
    ViolationStore store,
    ViolationTableState base,
  ) {
    final parsed = LintCruxNameResolver.parseRulePath(req.element.path);
    if (parsed == null) {
      return CxpDispatchResult(
        ack: RequestHighlightAck(
          inReplyTo: requestId,
          honored: false,
          reason: 'Malformed rule element path "${req.element.path}".',
        ),
      );
    }
    // Find the exact violation. Match on engine-namespaced ruleId
    // (Violation.ruleId already carries the engineId prefix per the
    // domain contract) and the source location.
    Violation? match;
    for (final v in store.all) {
      if (v.ruleId == parsed.ruleId &&
          v.location.file == parsed.file &&
          v.location.line == parsed.line &&
          v.location.column == parsed.column) {
        match = v;
        break;
      }
    }
    if (match == null) {
      return CxpDispatchResult(
        ack: RequestHighlightAck(
          inReplyTo: requestId,
          honored: false,
          reason: 'No matching violation in the active project.',
        ),
      );
    }
    // Clear the filter so the matched violation is visible; the
    // selection then highlights the single row. This matches the
    // common engineer expectation: peer asks "show me this", LintCrux
    // ensures it's in view.
    final cleared = base.copyWith(
      severities: const <Object>{}.cast(),
      engineIds: const <Object>{}.cast(),
      ruleSubstring: '',
      fileGlob: '',
    );
    return CxpDispatchResult(
      ack: RequestHighlightAck(inReplyTo: requestId, honored: true),
      tableState: cleared,
      selection: match,
    );
  }

  CxpDispatchResult _highlightSource(
    RequestHighlight req,
    String requestId,
    ViolationStore store,
    ViolationTableState base,
  ) {
    final parsed = LintCruxNameResolver.parseSourcePath(req.element.path);
    if (parsed == null) {
      return CxpDispatchResult(
        ack: RequestHighlightAck(
          inReplyTo: requestId,
          honored: false,
          reason: 'Malformed source element path "${req.element.path}".',
        ),
      );
    }
    // Find the violation closest to (file, line). Prefer exact-line
    // matches; fall back to the nearest line within the same file.
    Violation? best;
    var bestDistance = -1;
    for (final v in store.all) {
      if (v.location.file != parsed.file) continue;
      final distance = (v.location.line - parsed.line).abs();
      if (best == null || distance < bestDistance) {
        best = v;
        bestDistance = distance;
      }
    }
    // Set the file-glob filter to the target file so the user sees the
    // surrounding context in the table, not just the one selected row.
    final filtered = base.copyWith(
      severities: const <Object>{}.cast(),
      engineIds: const <Object>{}.cast(),
      ruleSubstring: '',
      fileGlob: parsed.file,
    );
    if (best == null) {
      // No matching violation, but the filter is still useful — the
      // requester wanted to see this file. Ack as honored (we did
      // something) without a selection.
      return CxpDispatchResult(
        ack: RequestHighlightAck(
          inReplyTo: requestId,
          honored: true,
          reason: 'No violations in file; filtered table to the file.',
        ),
        tableState: filtered,
      );
    }
    return CxpDispatchResult(
      ack: RequestHighlightAck(inReplyTo: requestId, honored: true),
      tableState: filtered,
      selection: best,
    );
  }

  CxpDispatchResult _filterByLocalPath(
    RequestHighlight req,
    String requestId,
    ViolationStore store,
    ViolationTableState base, {
    required String ruleSubstring,
  }) {
    // LintCrux does not own signals or modules. Filter the table to
    // entries whose engine-namespaced ruleId or message body mentions
    // the peer's local path. This is best-effort by design — the only
    // contract is "the table will narrow to entries that *could*
    // involve the named element."
    final filtered = base.copyWith(
      severities: const <Object>{}.cast(),
      engineIds: const <Object>{}.cast(),
      ruleSubstring: ruleSubstring,
      fileGlob: '',
    );
    final matches = store.filter(filtered.toFilter());
    return CxpDispatchResult(
      ack: RequestHighlightAck(
        inReplyTo: requestId,
        honored: true,
        reason: matches.isEmpty
            ? 'No violations mention "$ruleSubstring"; filter applied.'
            : null,
      ),
      tableState: filtered,
      selection: matches.isEmpty ? null : matches.first,
    );
  }

  Future<CxpDispatchResult> _dispatchRequestOpenSource(
    RequestOpenSource req,
    String requestId,
  ) async {
    if (req.line < 1) {
      return CxpDispatchResult(
        ack: RequestOpenSourceAck(
          inReplyTo: requestId,
          honored: false,
          reason: 'Invalid line ${req.line}.',
        ),
      );
    }
    // The last gate before a peer's string becomes an editor argv. There is
    // no shell on this path, so escaping buys nothing; what an editor's own
    // option parser reads as a flag is what containment closes — and CXP §11
    // asks for more than that: a path outside the directories the user has
    // opened is refused even when it is perfectly absolute. The reason rides
    // back in the ack and never repeats the path (CXP §9.11).
    final refusal = containment.refuse(req.filePath);
    if (refusal != null) {
      return CxpDispatchResult(
        ack: RequestOpenSourceAck(
          inReplyTo: requestId,
          honored: false,
          reason: refusal,
        ),
      );
    }
    final location = SourceLocation(
      file: req.filePath,
      line: req.line,
      column: req.column ?? 1,
    );
    final result = await openInEditor(location);
    return CxpDispatchResult(
      ack: RequestOpenSourceAck(
        inReplyTo: requestId,
        honored: result.success,
        reason: result.errorMessage,
      ),
      openSourceResult: result,
    );
  }
}
