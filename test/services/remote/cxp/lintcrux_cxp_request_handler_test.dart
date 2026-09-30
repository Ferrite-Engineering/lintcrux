// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';
import 'package:lintcrux/services/editor/click_to_source_service.dart';
import 'package:lintcrux/services/remote/cxp/lintcrux_cxp_request_handler.dart';
import 'package:lintcrux/services/remote/cxp/lintcrux_name_resolver.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';

import '../../../support/host_absolute_path.dart';

void main() {
  Violation mk({
    String engineId = 'verilator',
    String ruleId = 'verilator/UNUSEDSIGNAL',
    String file = '/proj/rtl/cpu.sv',
    int line = 42,
    int column = 7,
    String message = 'Signal unused',
    Severity severity = Severity.warning,
  }) {
    return Violation(
      engineId: engineId,
      ruleId: ruleId,
      severity: severity,
      message: message,
      location: SourceLocation(file: file, line: line, column: column),
    );
  }

  InboundCxpMessage inbound(CxpMessage body, {String from = 'peer-1'}) {
    final envelope = CxpEnvelope(
      messageId: 'msg-1',
      from: from,
      kind: body.kind,
      payload: body.toJson(),
    );
    return InboundCxpMessage(
      envelope: envelope,
      message: body,
      from: const PeerIdentity(
        peerId: 'peer-1',
        productName: 'wavecrux',
        productVersion: '0.7.0',
      ),
    );
  }

  late InMemoryViolationStore store;
  late ViolationTableState tableState;
  late List<SourceLocation> editorInvocations;
  late ClickToSourceResult editorResult;

  setUp(() {
    store = InMemoryViolationStore();
    tableState = ViolationTableState.initial;
    editorInvocations = <SourceLocation>[];
    editorResult = const ClickToSourceResult(
      success: true,
      command: RenderedEditorCommand(executable: 'code', arguments: []),
    );
  });

  LintCruxCxpRequestHandler buildHandler({CxpPathContainment? containment}) {
    return LintCruxCxpRequestHandler(
      violationStore: () => store,
      tableState: () => tableState,
      openInEditor: (loc) async {
        editorInvocations.add(loc);
        return editorResult;
      },
      containment: containment,
    );
  }

  group('RequestHighlight — ElementKind.rule', () {
    test(
      'honours an exact-match rule and selects the matching violation',
      () async {
        final v = mk();
        store.replaceFromEngine('verilator', [v]);
        final handler = buildHandler();

        final result = await handler.dispatch(
          inbound(
            RequestHighlight(
              element: ElementId(
                kind: ElementKind.rule,
                path: LintCruxNameResolver.encodeViolationAsRulePath(v)!,
              ),
            ),
          ),
        );

        expect(result.ack, isA<RequestHighlightAck>());
        final ack = result.ack as RequestHighlightAck;
        expect(ack.honored, isTrue);
        expect(ack.inReplyTo, 'msg-1');
        expect(result.selection, v);
        expect(result.tableState, isNotNull);
        // Clears filters so the violation is visible.
        expect(result.tableState!.severities, isEmpty);
        expect(result.tableState!.engineIds, isEmpty);
        expect(result.tableState!.ruleSubstring, '');
        expect(result.tableState!.fileGlob, '');
      },
    );

    test(
      'rejects with honored=false when the rule path is malformed',
      () async {
        final handler = buildHandler();
        final result = await handler.dispatch(
          inbound(
            const RequestHighlight(
              element: ElementId(kind: ElementKind.rule, path: 'no-at-sign'),
            ),
          ),
        );
        expect(result.selection, isNull);
        final ack = result.ack as RequestHighlightAck;
        expect(ack.honored, isFalse);
        expect(ack.reason, contains('Malformed'));
      },
    );

    test(
      'rejects with honored=false when no matching violation exists',
      () async {
        // Store has a different violation; the path encodes one we don't
        // hold.
        store.replaceFromEngine('verilator', [mk()]);
        final handler = buildHandler();
        final result = await handler.dispatch(
          inbound(
            const RequestHighlight(
              element: ElementId(
                kind: ElementKind.rule,
                path: 'verilator/OTHER@/other/file.sv:1:1',
              ),
            ),
          ),
        );
        final ack = result.ack as RequestHighlightAck;
        expect(ack.honored, isFalse);
        expect(ack.reason, contains('No matching violation'));
        expect(result.selection, isNull);
      },
    );
  });

  group('RequestHighlight — ElementKind.source', () {
    test(
      'filters to the file and selects the nearest-line violation',
      () async {
        final far = mk(line: 100);
        final near = mk();
        store.replaceFromEngine('verilator', [far, near]);
        final handler = buildHandler();

        final result = await handler.dispatch(
          inbound(
            RequestHighlight(
              element: ElementId(
                kind: ElementKind.source,
                path: LintCruxNameResolver.encodeSourcePath(
                  file: '/proj/rtl/cpu.sv',
                  line: 40,
                )!,
              ),
            ),
          ),
        );

        final ack = result.ack as RequestHighlightAck;
        expect(ack.honored, isTrue);
        expect(result.selection, near);
        expect(result.tableState!.fileGlob, '/proj/rtl/cpu.sv');
      },
    );

    test(
      'still ack honored when no violation in file (filter applied)',
      () async {
        final handler = buildHandler();
        final result = await handler.dispatch(
          inbound(
            const RequestHighlight(
              element: ElementId(
                kind: ElementKind.source,
                path: '/other/file.sv:1',
              ),
            ),
          ),
        );
        final ack = result.ack as RequestHighlightAck;
        expect(ack.honored, isTrue);
        expect(ack.reason, contains('No violations in file'));
        expect(result.tableState!.fileGlob, '/other/file.sv');
        expect(result.selection, isNull);
      },
    );

    test('rejects malformed source path', () async {
      final handler = buildHandler();
      final result = await handler.dispatch(
        inbound(
          const RequestHighlight(
            element: ElementId(
              kind: ElementKind.source,
              path: 'no-line-no-col',
            ),
          ),
        ),
      );
      final ack = result.ack as RequestHighlightAck;
      expect(ack.honored, isFalse);
    });
  });

  group('RequestHighlight — ElementKind.signal / instance', () {
    test(
      'signal kind sets ruleSubstring filter and selects first match',
      () async {
        // A violation whose message mentions the signal.
        final v = mk(
          message: 'Signal cpu_clk unused',
        );
        store.replaceFromEngine('verilator', [v]);
        final handler = buildHandler();
        final result = await handler.dispatch(
          inbound(
            const RequestHighlight(
              element: ElementId(
                kind: ElementKind.signal,
                path: 'top.cpu.cpu_clk',
              ),
            ),
          ),
        );
        // ruleSubstring matches against ruleId+message; "top.cpu.cpu_clk"
        // won't match anything literal, so the table narrows to zero.
        // The handler still acks honored=true with a reason.
        final ack = result.ack as RequestHighlightAck;
        expect(ack.honored, isTrue);
        expect(result.tableState!.ruleSubstring, 'top.cpu.cpu_clk');
        expect(result.selection, isNull);
      },
    );

    test('instance kind sets ruleSubstring filter', () async {
      store.replaceFromEngine('verilator', [mk()]);
      final handler = buildHandler();
      final result = await handler.dispatch(
        inbound(
          const RequestHighlight(
            element: ElementId(
              kind: ElementKind.instance,
              path: 'top.cpu',
            ),
          ),
        ),
      );
      final ack = result.ack as RequestHighlightAck;
      expect(ack.honored, isTrue);
      expect(result.tableState!.ruleSubstring, 'top.cpu');
    });
  });

  group('RequestHighlight — unsupported kinds', () {
    test('returns honored=false for breakpoint / marker / etc.', () async {
      final handler = buildHandler();
      for (final kind in <ElementKind>[
        ElementKind.scope,
        ElementKind.net,
        ElementKind.port,
        ElementKind.marker,
        ElementKind.test,
        ElementKind.breakpoint,
      ]) {
        final result = await handler.dispatch(
          inbound(
            RequestHighlight(
              element: ElementId(kind: kind, path: 'anything'),
            ),
          ),
        );
        final ack = result.ack as RequestHighlightAck;
        expect(ack.honored, isFalse, reason: 'kind: $kind');
        expect(ack.reason, contains(kind.name), reason: 'kind: $kind');
        expect(result.tableState, isNull, reason: 'kind: $kind');
        expect(result.selection, isNull, reason: 'kind: $kind');
      }
    });

    test(
      'declines an element kind this build has never heard of, gracefully',
      () async {
        // `ElementKind` is an open wire type: a peer on a newer protocol
        // revision (or a third-party tool) can name a kind this build does
        // not model. That must degrade to a plain "not honored" ack — never
        // a throw, never a dropped reply, or an older LintCrux becomes
        // crashable by a newer peer's vocabulary.
        final handler = buildHandler();
        final unknown = ElementKind('quantum-flux-capacitor');
        expect(
          unknown.known,
          isNull,
          reason: 'the fixture must actually be an unmodelled kind',
        );

        final result = await handler.dispatch(
          inbound(
            RequestHighlight(
              element: ElementId(kind: unknown, path: 'anything'),
            ),
          ),
        );

        final ack = result.ack as RequestHighlightAck;
        expect(ack.honored, isFalse);
        // The unrecognised wire string is echoed back verbatim so the
        // originator can tell which of its requests went unserved.
        expect(ack.reason, contains('quantum-flux-capacitor'));
        expect(result.tableState, isNull);
        expect(result.selection, isNull);
      },
    );
  });

  group('RequestOpenSource', () {
    test('invokes the editor and acks honored=true on success', () async {
      final handler = buildHandler();
      final file = hostAbsolute('/proj/rtl/cpu.sv');
      final result = await handler.dispatch(
        inbound(
          RequestOpenSource(
            filePath: file,
            line: 42,
            column: 7,
          ),
        ),
      );
      expect(editorInvocations, hasLength(1));
      expect(editorInvocations.single.file, file);
      expect(editorInvocations.single.line, 42);
      expect(editorInvocations.single.column, 7);
      final ack = result.ack as RequestOpenSourceAck;
      expect(ack.honored, isTrue);
      expect(ack.inReplyTo, 'msg-1');
    });

    test('defaults missing column to 1', () async {
      final handler = buildHandler();
      await handler.dispatch(
        inbound(
          RequestOpenSource(
            filePath: hostAbsolute('/proj/rtl/cpu.sv'),
            line: 1,
          ),
        ),
      );
      expect(editorInvocations.single.column, 1);
    });

    test('forwards the editor failure as ack honored=false + reason', () async {
      editorResult = const ClickToSourceResult(
        success: false,
        command: RenderedEditorCommand(executable: 'code', arguments: []),
        errorMessage: 'No such file',
      );
      final handler = buildHandler();
      final result = await handler.dispatch(
        inbound(
          RequestOpenSource(
            filePath: hostAbsolute('/x.sv'),
            line: 1,
          ),
        ),
      );
      final ack = result.ack as RequestOpenSourceAck;
      expect(ack.honored, isFalse);
      expect(ack.reason, 'No such file');
    });

    test('rejects line < 1', () async {
      final handler = buildHandler();
      final result = await handler.dispatch(
        inbound(
          const RequestOpenSource(
            filePath: '/x.sv',
            line: 0,
          ),
        ),
      );
      expect(editorInvocations, isEmpty);
      final ack = result.ack as RequestOpenSourceAck;
      expect(ack.honored, isFalse);
      expect(ack.reason, contains('Invalid line'));
    });

    // The handler is the last gate before a peer's string becomes an editor
    // argv, and it is reached without `LocalCxpServer`'s screen in between
    // here — so this proves its own check, not the server's.
    //
    // MUTATION: deleting the `containment.refuse` block in
    // `_dispatchRequestOpenSource` makes both of these red.
    test('refuses a path outside the open directories without invoking the '
        'editor', () async {
      final handler = buildHandler(
        containment: CxpPathContainment(
          roots: () => <String>[hostAbsolute('/proj')],
        ),
      );
      final outside = hostAbsolute('/etc/passwd');
      final result = await handler.dispatch(
        inbound(RequestOpenSource(filePath: outside, line: 1)),
      );
      expect(editorInvocations, isEmpty);
      final ack = result.ack as RequestOpenSourceAck;
      expect(ack.honored, isFalse);
      expect(ack.reason, contains('outside the directories'));
      expect(ack.reason, isNot(contains(outside)));
    });

    test(
      'refuses an option-shaped path even with no roots configured',
      () async {
        final handler = buildHandler();
        final result = await handler.dispatch(
          inbound(const RequestOpenSource(filePath: '--help', line: 1)),
        );
        expect(editorInvocations, isEmpty);
        final ack = result.ack as RequestOpenSourceAck;
        expect(ack.honored, isFalse);
        expect(ack.reason, contains('absolute path'));
      },
    );
  });

  group('Unknown message kinds', () {
    test(
      'NotifySelection (broadcast LintCrux did not subscribe to) returns'
      ' an unsupported ErrorResponse, not a fabricated highlight ack',
      () async {
        final handler = buildHandler();
        final result = await handler.dispatch(
          inbound(const NotifySelection(elements: <ElementId>[])),
        );
        expect(result.ack, isA<ErrorResponse>());
        expect(result.ack, isNot(isA<RequestHighlightAck>()));
        final ack = result.ack as ErrorResponse;
        expect(ack.code, CxpErrorCode.unsupported);
        expect(ack.message, contains('does not handle'));
        expect(ack.inReplyTo, isNotEmpty);
        expect(result.tableState, isNull);
        expect(result.selection, isNull);
      },
    );
  });

  // Two routes open a project a peer named, and they keep different rules:
  // `request_open_artifact` (the user asked for the project) goes through
  // `openRequestedArtifact`, held to the floor in production; the
  // `crux.design_id` fallback a highlight takes goes through
  // `resolveAndOpenArtifact`, which keeps the roots. The rules themselves are
  // proven over a socket in `test/features/remote/cxp_open_artifact_test.dart`;
  // these pin which route each message takes.
  group('RequestOpenArtifact', () {
    LintCruxCxpRequestHandler buildHandlerWith({
      Future<bool> Function(String designId)? fallback,
      Future<CxpArtifactOpenOutcome> Function(String designId, String? hint)?
      requested,
    }) {
      return LintCruxCxpRequestHandler(
        violationStore: () => store,
        tableState: () => tableState,
        openInEditor: (loc) async {
          editorInvocations.add(loc);
          return editorResult;
        },
        resolveAndOpenArtifact: fallback,
        openRequestedArtifact: requested,
      );
    }

    test(
      'opens the design project and acks honored for a "source" kind',
      () async {
        final asked = <(String, String?)>[];
        final handler = buildHandlerWith(
          requested: (designId, hint) async {
            asked.add((designId, hint));
            return (honored: true, reason: null);
          },
        );
        final result = await handler.dispatch(
          inbound(
            const RequestOpenArtifact(
              designId: 'design-7',
              artifactKind: 'source',
            ),
          ),
        );
        expect(asked, <(String, String?)>[('design-7', null)]);
        expect(result.ack, isA<RequestOpenArtifactAck>());
        final ack = result.ack as RequestOpenArtifactAck;
        expect(ack.honored, isTrue);
        expect(ack.reason, isNull);
      },
    );

    // The hint is the fallback when nothing is recorded (CXP §9.10), so it
    // has to reach the opener. MUTATION: passing `null` for the hint in
    // `_dispatchRequestOpenArtifact` makes this red.
    test("hands the request's path hint to the opener", () async {
      final asked = <(String, String?)>[];
      final handler = buildHandlerWith(
        requested: (designId, hint) async {
          asked.add((designId, hint));
          return (honored: true, reason: null);
        },
      );
      await handler.dispatch(
        inbound(
          const RequestOpenArtifact(
            designId: 'design-7',
            artifactKind: 'source',
            path: '/work/uart/uart.lintcrux',
          ),
        ),
      );
      expect(asked, <(String, String?)>[
        ('design-7', '/work/uart/uart.lintcrux'),
      ]);
    });

    test(
      'declines a non-source artifact kind without calling the opener',
      () async {
        var called = false;
        final handler = buildHandlerWith(
          requested: (_, _) async {
            called = true;
            return (honored: true, reason: null);
          },
        );
        final result = await handler.dispatch(
          inbound(
            const RequestOpenArtifact(
              designId: 'design-7',
              artifactKind: 'waveform',
            ),
          ),
        );
        expect(called, isFalse);
        final ack = result.ack as RequestOpenArtifactAck;
        expect(ack.honored, isFalse);
        expect(ack.reason, contains('waveform'));
      },
    );

    test("acks honored=false with the opener's reason", () async {
      final handler = buildHandlerWith(
        requested: (_, _) async =>
            (honored: false, reason: 'file_path must be an absolute path'),
      );
      final result = await handler.dispatch(
        inbound(
          const RequestOpenArtifact(
            designId: 'design-x',
            artifactKind: 'source',
          ),
        ),
      );
      final ack = result.ack as RequestOpenArtifactAck;
      expect(ack.honored, isFalse);
      expect(ack.reason, 'file_path must be an absolute path');
    });

    test('acks honored=false when no opener is wired (no workspace)', () async {
      final handler = buildHandler();
      final result = await handler.dispatch(
        inbound(
          const RequestOpenArtifact(
            designId: 'design-7',
            artifactKind: 'source',
          ),
        ),
      );
      expect((result.ack as RequestOpenArtifactAck).honored, isFalse);
    });

    // MUTATION: calling `resolveAndOpenArtifact` from
    // `_dispatchRequestOpenArtifact` makes this red.
    test(
      'never goes through the crux.design_id fallback, which keeps the roots',
      () async {
        final fallback = <String>[];
        final handler = buildHandlerWith(
          fallback: (designId) async {
            fallback.add(designId);
            return true;
          },
        );
        final result = await handler.dispatch(
          inbound(
            const RequestOpenArtifact(
              designId: 'design-7',
              artifactKind: 'source',
            ),
          ),
        );
        expect(fallback, isEmpty);
        expect((result.ack as RequestOpenArtifactAck).honored, isFalse);
      },
    );

    test(
      'a RequestHighlight(rule) miss opens the design from crux.design_id',
      () async {
        // Nothing in the store, so the local rule highlight misses.
        final opened = <String>[];
        var requested = false;
        final handler = buildHandlerWith(
          fallback: (designId) async {
            opened.add(designId);
            return true;
          },
          requested: (_, _) async {
            requested = true;
            return (honored: true, reason: null);
          },
        );
        final rulePath = LintCruxNameResolver.encodeViolationAsRulePath(mk())!;
        final result = await handler.dispatch(
          inbound(
            RequestHighlight(
              element: ElementId(kind: ElementKind.rule, path: rulePath),
              metadata: const <String, Object?>{
                cxpDesignIdMetadataKey: 'design-9',
              },
            ),
          ),
        );
        expect(opened, <String>['design-9']);
        expect(
          requested,
          isFalse,
          reason: 'the fallback keeps the roots; it is not the floor route',
        );
        final ack = result.ack as RequestHighlightAck;
        expect(ack.honored, isTrue);
      },
    );

    test(
      'a RequestHighlight(rule) miss without an opener stays honored=false',
      () async {
        final handler = buildHandler();
        final rulePath = LintCruxNameResolver.encodeViolationAsRulePath(mk())!;
        final result = await handler.dispatch(
          inbound(
            RequestHighlight(
              element: ElementId(kind: ElementKind.rule, path: rulePath),
              metadata: const <String, Object?>{
                cxpDesignIdMetadataKey: 'design-9',
              },
            ),
          ),
        );
        expect((result.ack as RequestHighlightAck).honored, isFalse);
      },
    );
  });
}
