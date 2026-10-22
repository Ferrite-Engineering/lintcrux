// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';
import 'package:lintcrux/features/remote/providers/cxp_request_handler_provider.dart';
import 'package:lintcrux/services/editor/click_to_source_service.dart';
import 'package:lintcrux/services/remote/cxp/cxp_project_open_handle.dart';
import 'package:lintcrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:lintcrux/services/remote/cxp/lintcrux_cxp_request_handler.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';
import 'package:path/path.dart' as p;

import '../../../support/host_absolute_path.dart';
import '../../../support/telemetry_test_store.dart';

/// CXP 1.3 section 9.11 and conformance item 22: the `reason` of a refusal
/// names the kind of refusal and nothing the sender supplied. Every refusal
/// path of LintCrux's request handler is driven here with a request whose
/// path, design id, file name and kind name are unmistakable, and the reason
/// is searched for each of them.
///
/// MUTATION: interpolating a path, a design id, an element or artifact kind,
/// or an editor's own error text into any reason turns the matching case red.
InboundCxpMessage _inbound(CxpMessage body) => InboundCxpMessage(
  envelope: CxpEnvelope(
    messageId: 'msg-1',
    from: 'peer-1',
    kind: body.kind,
    payload: body.toJson(),
  ),
  message: body,
  from: const PeerIdentity(
    peerId: 'peer-1',
    productName: 'test',
    productVersion: '0.0.0',
  ),
);

/// The sentinel segments of [value] read as a path in either separator style:
/// the ones this test minted, which start with `zq`.
Iterable<String> _segments(String value) =>
    value.split(RegExp(r'[/\\]')).where((s) => s.startsWith('zq'));

/// Fails when [ack] is not a refusal or when its reason contains any of
/// [sent], whole or by path segment.
void _expectNothingEchoed(CxpMessage? ack, List<String> sent) {
  final (bool honored, String? reason) = switch (ack) {
    RequestHighlightAck(:final honored, :final reason) => (honored, reason),
    RequestOpenSourceAck(:final honored, :final reason) => (honored, reason),
    RequestOpenArtifactAck(:final honored, :final reason) => (honored, reason),
    _ => throw StateError('not an acknowledgement: $ack'),
  };
  expect(honored, isFalse);
  expect(reason, isNotNull);
  expect(reason, isNotEmpty);
  for (final value in sent) {
    expect(reason, isNot(contains(value)), reason: 'echoes "$value"');
    for (final segment in _segments(value)) {
      expect(reason, isNot(contains(segment)), reason: 'echoes "$segment"');
    }
  }
}

void _deleteQuietly(Directory dir) {
  try {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  } on FileSystemException {
    /* best effort */
  }
}

void main() {
  group('the handler on its own', () {
    late ClickToSourceResult editorResult;

    setUp(() {
      editorResult = const ClickToSourceResult(
        success: true,
        command: RenderedEditorCommand(executable: 'zqeditor', arguments: []),
      );
    });

    LintCruxCxpRequestHandler buildHandler({
      CxpPathContainment? containment,
      bool withOpener = true,
    }) => LintCruxCxpRequestHandler(
      violationStore: InMemoryViolationStore.new,
      tableState: () => ViolationTableState.initial,
      openInEditor: (location) async => editorResult,
      containment: containment,
      openRequestedArtifact: withOpener
          ? (designId, hint) async => (honored: true, reason: null)
          : null,
    );

    Future<CxpMessage?> dispatch(
      LintCruxCxpRequestHandler handler,
      CxpMessage body,
    ) async => (await handler.dispatch(_inbound(body))).ack;

    test('a rule path that is malformed', () async {
      const path = 'zqmalformed/zqrule';
      final ack = await dispatch(
        buildHandler(),
        const RequestHighlight(
          element: ElementId(kind: ElementKind.rule, path: path),
        ),
      );
      _expectNothingEchoed(ack, <String>[path]);
    });

    test('a rule that matches no violation', () async {
      const path = 'zqengine/ZQRULE@/zqdir/zqfile.sv:1:1';
      final ack = await dispatch(
        buildHandler(),
        const RequestHighlight(
          element: ElementId(kind: ElementKind.rule, path: path),
        ),
      );
      _expectNothingEchoed(ack, <String>[path, '/zqdir/zqfile.sv']);
    });

    test('a source path that is malformed', () async {
      const path = 'zqmalformed/zqsource';
      final ack = await dispatch(
        buildHandler(),
        const RequestHighlight(
          element: ElementId(kind: ElementKind.source, path: path),
        ),
      );
      _expectNothingEchoed(ack, <String>[path]);
    });

    test(
      'a kind LintCrux does not represent and one it never heard of',
      () async {
        const path = 'zqtop.zqsub.zqsig';
        for (final kind in <ElementKind>[
          ElementKind.scope,
          ElementKind.net,
          ElementKind.port,
          ElementKind.marker,
          ElementKind.test,
          ElementKind.breakpoint,
          ElementKind.property,
          ElementKind.timingPath,
          ElementKind.cell,
          ElementKind('zqkind_unheard'),
        ]) {
          final ack = await dispatch(
            buildHandler(),
            RequestHighlight(
              element: ElementId(kind: kind, path: path),
            ),
          );
          _expectNothingEchoed(ack, <String>[path, 'zqkind_unheard']);
        }
      },
    );

    test('an artifact kind LintCrux does not open', () async {
      const designId = 'zqdesign-kind-0123456789abcdef';
      const kind = 'zqkind_artifact';
      final ack = await dispatch(
        buildHandler(),
        const RequestOpenArtifact(
          designId: designId,
          artifactKind: kind,
          path: '/zqdir/zqrun.vcd',
        ),
      );
      _expectNothingEchoed(ack, <String>[designId, kind, '/zqdir/zqrun.vcd']);
    });

    test('an artifact open when no workspace is available', () async {
      const designId = 'zqdesign-nows-0123456789abcdef';
      final ack = await dispatch(
        buildHandler(withOpener: false),
        const RequestOpenArtifact(designId: designId, artifactKind: 'source'),
      );
      _expectNothingEchoed(ack, <String>[designId]);
    });

    test('a line that is not valid', () async {
      final file = hostAbsolute('/zqrtl/zqdir/zqalu.sv');
      final ack = await dispatch(
        buildHandler(),
        RequestOpenSource(filePath: file, line: 0),
      );
      _expectNothingEchoed(ack, <String>[file]);
    });

    test('a file outside the directories the user has opened', () async {
      final file = hostAbsolute('/zqoutside/zqdir/zqpasswd.sv');
      final ack = await dispatch(
        buildHandler(
          containment: CxpPathContainment(
            roots: () => <String>[hostAbsolute('/zqrtl')],
          ),
        ),
        RequestOpenSource(filePath: file, line: 1),
      );
      _expectNothingEchoed(ack, <String>[file]);
    });

    test('a file that is not an absolute path', () async {
      const file = 'zqrelative/zqalu.sv';
      final ack = await dispatch(
        buildHandler(),
        const RequestOpenSource(filePath: file, line: 1),
      );
      _expectNothingEchoed(ack, <String>[file]);
    });

    test('an editor that fails, whatever its own message says', () async {
      final file = hostAbsolute('/zqrtl/zqdir/zqalu.sv');
      editorResult = ClickToSourceResult(
        success: false,
        command: const RenderedEditorCommand(
          executable: '/zqbin/zqeditor',
          arguments: [],
        ),
        errorMessage: 'Failed to launch /zqbin/zqeditor: cannot open $file',
      );
      final ack = await dispatch(
        buildHandler(),
        RequestOpenSource(filePath: file, line: 3),
      );
      _expectNothingEchoed(ack, <String>[file, '/zqbin/zqeditor']);
    });

    test('an editor that refuses a location that is not absolute', () async {
      final file = hostAbsolute('/zqrtl/zqdir/zqalu.sv');
      editorResult = const ClickToSourceResult(
        success: false,
        command: RenderedEditorCommand(executable: 'zqeditor', arguments: []),
        errorMessage: ClickToSourceService.refusedNonAbsolutePathMessage,
      );
      final ack = await dispatch(
        buildHandler(),
        RequestOpenSource(filePath: file, line: 3),
      );
      _expectNothingEchoed(ack, <String>[file]);
    });
  });

  group('the production wiring', () {
    late Directory opened;
    late Directory never;
    late Directory storeDir;
    late bool openerAccepts;

    setUp(() {
      opened = Directory.systemTemp.createTempSync('zqlc_reason_opened_');
      never = Directory.systemTemp.createTempSync('zqlc_reason_never_');
      storeDir = Directory.systemTemp.createTempSync('zqlc_reason_store_');
      openerAccepts = true;
    });

    tearDown(() {
      <Directory>[opened, never, storeDir].forEach(_deleteQuietly);
    });

    File file(Directory dir, String name, [String content = '{}']) =>
        File(p.join(dir.path, name))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(content);

    ProviderContainer boot() {
      final openedProject = file(opened, 'zqopened.lintcrux');
      final container = ProviderContainer(
        overrides: <Override>[
          ...telemetryDeclinedOverrides(),
          cxpWorkspaceStoreProvider.overrideWith(
            (ref) => CxpWorkspaceStore(
              workspaceDirectory: storeDir.path,
              containment: ref.watch(cxpPathContainmentProvider),
            ),
          ),
          cxpProjectOpenHandleProvider.overrideWithValue(
            CxpProjectOpenHandle()
              ..projectPaths = (() => <String>[openedProject.path])
              ..opener = (path) async => openerAccepts,
          ),
          violationStoreProvider.overrideWithValue(InMemoryViolationStore()),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Future<CxpMessage?> ask(
      ProviderContainer container, {
      required String designId,
      String? hint,
    }) async =>
        (await container
                .read(cxpRequestHandlerProvider)
                .dispatch(
                  _inbound(
                    RequestOpenArtifact(
                      designId: designId,
                      artifactKind: 'source',
                      path: hint,
                    ),
                  ),
                ))
            .ack;

    test('a design with no recorded project and no hint', () async {
      const designId = 'zqdesign-unrecorded-0123456789';
      final ack = await ask(boot(), designId: designId);
      _expectNothingEchoed(ack, <String>[designId]);
    });

    test('a hint that is not an absolute path', () async {
      const designId = 'zqdesign-relative-0123456789a';
      const hint = 'zqrelative/zqproject.lintcrux';
      final ack = await ask(boot(), designId: designId, hint: hint);
      _expectNothingEchoed(ack, <String>[designId, hint]);
    });

    test('a hint that names no file here', () async {
      const designId = 'zqdesign-missing-0123456789ab';
      final hint = p.join(never.path, 'zqdeleted', 'zqproject.lintcrux');
      final ack = await ask(boot(), designId: designId, hint: hint);
      _expectNothingEchoed(ack, <String>[designId, hint]);
    });

    test('a project the opener declines', () async {
      const designId = 'zqdesign-declined-0123456789a';
      final project = file(never, 'zqproject.lintcrux');
      openerAccepts = false;
      final ack = await ask(boot(), designId: designId, hint: project.path);
      _expectNothingEchoed(ack, <String>[designId, project.path]);
    });

    test('a design manifest LintCrux cannot use', () async {
      const designId = 'zqdesign-manifest-0123456789a';
      final manifest = file(
        never,
        'zqdesign.crux-project',
        'zqjunk: not a manifest',
      );
      final ack = await ask(boot(), designId: designId, hint: manifest.path);
      _expectNothingEchoed(ack, <String>[designId, manifest.path]);
    });

    test('a design manifest that names another manifest', () async {
      const designId = 'zqdesign-nested-0123456789ab';
      final nested = Directory(p.join(never.path, 'zqnested'))..createSync();
      file(nested, 'zqinner.crux-project', 'version: 1\n');
      final design = file(
        never,
        'zqdesign.crux-project',
        'version: 1\nartifacts:\n  lint: zqnested/zqinner.crux-project\n',
      );
      final ack = await ask(boot(), designId: designId, hint: design.path);
      _expectNothingEchoed(ack, <String>[designId, design.path]);
    });
  });
}
