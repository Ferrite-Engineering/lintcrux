// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_window_chrome/crux_window_chrome.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/app_settings.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/services/remote/cxp/cxp_project_open_handle.dart';
import 'package:lintcrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:lintcrux/services/remote/cxp/lintcrux_name_resolver.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';
import 'package:path/path.dart' as p;
import '../../support/telemetry_test_store.dart';

/// `request_open_artifact`: a peer asks LintCrux to open a design's
/// `.lintcrux` project, named by `design_id`, with an optional `path` hint.
/// LintCrux resolves the file through the shared workspace store, falls back
/// to the hint, swaps a `<design>.crux-project` manifest for the project it
/// names, and opens the result — so every path that reaches the opener here
/// was chosen, directly or through a record, by another process.
///
/// The route is held to the floor — absolute, well-formed, the exact string
/// opened — and not to the projects the user has opened: it exists to open a
/// project LintCrux has never seen, which is what "Open in LintCrux Desktop"
/// in VS Code sends (`kCxpOpenArtifactContainment` says why). The
/// `crux.design_id` fallback a highlight takes keeps the roots, and the last
/// group proves that it still does.
///
/// Everything runs through the production wiring — `cxpRequestHandlerProvider`
/// and the real `cxpPathContainmentProvider`, whose roots are the directories
/// of the projects the handle reports opened. Most tests dispatch straight to
/// the handler, so it sees exactly what a peer sent; the socket tests go
/// through the server the lifecycle provider builds, whose wire screen runs
/// first.
void main() {
  late Directory opened;
  late Directory never;
  late Directory storeDir;
  late Directory peersDir;
  late List<String> openerCalls;

  setUp(() {
    opened = Directory.systemTemp.createTempSync('lc_artifact_opened_');
    never = Directory.systemTemp.createTempSync('lc_artifact_never_');
    storeDir = Directory.systemTemp.createTempSync('lc_artifact_store_');
    peersDir = Directory.systemTemp.createTempSync('lc_artifact_peers_');
    openerCalls = <String>[];
    // An honoured open nudges the window's attention; these plain `test()`
    // bodies have no binding for the platform channel.
    windowAttentionRequester = const NoopWindowAttentionRequester();
  });

  tearDown(() {
    windowAttentionRequester = const MethodChannelWindowAttentionRequester();
    <Directory>[opened, never, storeDir, peersDir].forEach(_deleteQuietly);
  });

  File project(Directory dir, String name) => File(p.join(dir.path, name))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('{}');

  File manifest(Directory dir, String lint) =>
      File(p.join(dir.path, 'design.crux-project'))
        ..writeAsStringSync('version: 1\nartifacts:\n  lint: $lint\n');

  Future<void> record(String designId, String path) =>
      CxpWorkspaceStore(workspaceDirectory: storeDir.path).upsertArtifact(
        designId: designId,
        kind: kCxpLintcruxSourceKind,
        path: path,
        producer: 'peer',
      );

  /// The production wiring, with one opened project in [opened] and an
  /// opener that records what it is handed.
  ProviderContainer boot() {
    final openedProject = project(opened, 'opened.lintcrux');
    final container = ProviderContainer(
      overrides: <Override>[
        ...telemetryDeclinedOverrides(),
        // The production store, pointed at a temp directory and carrying
        // the production rule.
        cxpWorkspaceStoreProvider.overrideWith(
          (ref) => CxpWorkspaceStore(
            workspaceDirectory: storeDir.path,
            containment: ref.watch(cxpPathContainmentProvider),
          ),
        ),
        // What `WorkspaceRoot` publishes: the projects the user has opened,
        // and an opener. Overriding the handle rather than the rule keeps
        // the production roots function in the path under test.
        cxpProjectOpenHandleProvider.overrideWithValue(
          CxpProjectOpenHandle()
            ..projectPaths = (() => <String>[openedProject.path])
            ..opener = (path) async {
              openerCalls.add(path);
              return true;
            },
        ),
        appSettingsProvider.overrideWith(_CxpOnEphemeralPort.new),
        violationStoreProvider.overrideWithValue(InMemoryViolationStore()),
        cxpManifestDirectoryProvider.overrideWith((ref) async => peersDir.path),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<RequestOpenArtifactAck> ask(
    ProviderContainer container, {
    String designId = 'unrecorded',
    String? hint,
  }) async {
    final result = await container
        .read(cxpRequestHandlerProvider)
        .dispatch(
          _inbound(
            RequestOpenArtifact(
              designId: designId,
              artifactKind: kCxpLintcruxSourceKind,
              path: hint,
            ),
          ),
        );
    return result.ack as RequestOpenArtifactAck;
  }

  group('request_open_artifact', () {
    test('a recorded project inside the opened projects is opened', () async {
      final file = project(opened, 'sibling.lintcrux');
      await record('d1', file.path);
      final container = boot();
      final ack = await ask(container, designId: 'd1');
      expect(ack.honored, isTrue, reason: ack.reason);
      expect(ack.reason, isNull);
      expect(openerCalls, <String>[file.path]);
    });

    test('no record and no hint is declined', () async {
      final container = boot();
      final ack = await ask(container, designId: 'unknown');
      expect(ack.honored, isFalse);
      expect(ack.reason, contains('No source artifact recorded'));
      expect(openerCalls, isEmpty);
    });

    // The project the VS Code extension hands over is, as often as not, one
    // LintCrux has never opened, and with no record the hint is all there
    // is. MUTATION: checking the path with `cxpPathContainmentProvider` in
    // `openRequestedArtifact` instead of `kCxpOpenArtifactContainment` makes
    // this red; so does ignoring the hint.
    test('with no record, a hint to a project never opened is opened: the '
        'floor applies, not the roots', () async {
      final file = project(never, 'never.lintcrux');
      final container = boot();
      expect(
        container.read(cxpPathContainmentProvider).allows(file.path),
        isFalse,
        reason: 'the premise: the roots would refuse this project',
      );
      final ack = await ask(container, hint: file.path);
      expect(ack.honored, isTrue, reason: ack.reason);
      expect(openerCalls, <String>[file.path]);
    });

    // The extension publishes the project before it sends, so this is the
    // path its hand-off normally takes. The store the app provides is rooted
    // and would drop the record; the route reads the same directory under
    // the floor. MUTATION: resolving through
    // `resolveLintcruxSourceArtifactPath` (the rooted store) in
    // `openRequestedArtifact` makes this red.
    test('a record for a project never opened is opened, though the rooted '
        'store drops it', () async {
      final file = project(never, 'published.lintcrux');
      await record('d-published', file.path);
      final container = boot();
      expect(
        container
            .read(cxpWorkspaceStoreProvider)
            .resolveArtifact(
              'd-published',
              kCxpLintcruxSourceKind,
            ),
        isNull,
        reason: 'the premise: the rooted store drops this record',
      );
      final ack = await ask(container, designId: 'd-published');
      expect(ack.honored, isTrue, reason: ack.reason);
      expect(openerCalls, <String>[file.path]);
    });

    // The receiver's own resolution comes first (CXP §9.10), wherever the
    // record points. MUTATION: resolving through the rooted store makes this
    // fall back to the hint, and it goes red.
    test('a record outside the opened projects wins over a hint inside '
        'them', () async {
      final recorded = project(never, 'recorded.lintcrux');
      final hinted = project(opened, 'hinted.lintcrux');
      await record('d2', recorded.path);
      final container = boot();
      final ack = await ask(container, designId: 'd2', hint: hinted.path);
      expect(ack.honored, isTrue, reason: ack.reason);
      expect(openerCalls, <String>[recorded.path]);
    });

    // The floor is what stands between a peer and an open now, so each of
    // its refusals is pinned by a case only it can refuse.
    group('the floor refuses', () {
      // Relative to where LintCrux runs, this names a real project, so
      // nothing after the floor would stop it. MUTATION: deleting the
      // `refuse(path)` check at the top of `openCxpProject` opens it, and
      // this goes red.
      test('a relative path, even one naming a file from where LintCrux '
          'runs', () async {
        // Under the working directory, not the system temp directory: on
        // Windows the two can be on different drives, and no relative path
        // crosses a drive, so `p.relative` would answer absolute.
        final scratch = Directory(p.join('build', 'test_tmp'))
          ..createSync(recursive: true);
        final here = scratch.createTempSync('lc_artifact_relative_');
        addTearDown(() => _deleteQuietly(here));
        final relative = p.relative(project(here, 'relative.lintcrux').path);
        expect(p.isRelative(relative), isTrue);
        expect(
          FileSystemEntity.typeSync(relative),
          FileSystemEntityType.file,
          reason: 'the case must name a real file, or it proves nothing',
        );
        final container = boot();
        final ack = await ask(container, hint: relative);
        expect(ack.honored, isFalse);
        expect(ack.reason, 'file_path must be an absolute path');
        expect(openerCalls, isEmpty);
      });

      // A NUL ends the name where the operating system reads it, so what was
      // checked is not what would be opened.
      test('a path carrying a NUL', () async {
        final file = project(never, 'nul.lintcrux');
        final container = boot();
        for (final hint in <String>[
          '${file.path} ',
          '${file.path} .txt',
          '${never.path} /nul.lintcrux',
        ]) {
          final ack = await ask(container, hint: hint);
          expect(ack.honored, isFalse, reason: 'hint ${hint.codeUnits}');
          expect(ack.reason, 'file_path contains a NUL character');
        }
        expect(openerCalls, isEmpty);
      });

      // The string checked is the string opened. A trailing space is part of
      // a POSIX file name, so `padded.lintcrux ` is a real file here and a
      // different one from `padded.lintcrux`; a check that trimmed first
      // would pass the one name and open the other. The shared floor refuses
      // the padded hint in its own words, and a padded record never leaves
      // the store: it is dropped under the same floor, so the request has
      // nothing recorded. MUTATION: handing `openCxpProject` a refusal that
      // trims before it asks the floor opens `padded.lintcrux `, and this
      // goes red.
      test('a path padded with white space, though the padded name is a real '
          'file', () async {
        project(never, 'padded.lintcrux');
        final trailing = project(never, 'padded.lintcrux ').path;
        expect(
          FileSystemEntity.typeSync(trailing),
          FileSystemEntityType.file,
          reason: 'the case must name a real file, or it proves nothing',
        );
        final plain = p.join(never.path, 'padded.lintcrux');
        final container = boot();
        for (final hint in <String>[trailing, ' $plain', '$plain\t']) {
          final ack = await ask(container, hint: hint);
          expect(ack.honored, isFalse, reason: 'hint ${hint.codeUnits}');
          expect(ack.reason, 'file_path begins or ends with white space');
        }

        // The same name arriving as a record rather than a hint: the store
        // reads records under the floor, so it drops this one.
        await record('d-padded', trailing);
        final ack = await ask(container, designId: 'd-padded');
        expect(ack.honored, isFalse);
        expect(
          ack.reason,
          'No source artifact recorded for design "d-padded".',
        );
        expect(openerCalls, isEmpty);
      });
    });

    // A hint can name the sender's path on its own machine layout, or a
    // project since deleted. MUTATION: deleting the `FileSystemEntity`
    // check in `openCxpProject` hands the opener a path that is not there,
    // and this goes red.
    test('a hint naming no file here is declined before the opener', () async {
      final container = boot();
      for (final missing in <String>[
        p.join(never.path, 'deleted.lintcrux'),
        never.path, // a directory, not a file
      ]) {
        final ack = await ask(container, hint: missing);
        expect(ack.honored, isFalse, reason: missing);
        expect(ack.reason, 'the artifact is not a file here');
      }
      expect(openerCalls, isEmpty);
    });

    // A `<design>.crux-project` is swapped for the lint project it names
    // before the open, and the floor judges the swapped path: the opener is
    // handed the `.lintcrux` project, which it has nothing to swap, so the
    // string checked is the string opened (CXP §11.3). MUTATION: handing the
    // opener `path` rather than the swapped `project` in `openCxpProject`
    // makes this red.
    test('a design manifest is swapped for its lint project before the open, '
        'and the opener is handed the project', () async {
      final lint = project(never, 'uart.lintcrux');
      final design = manifest(never, 'uart.lintcrux');
      final container = boot();
      final ack = await ask(container, hint: design.path);
      expect(ack.honored, isTrue, reason: ack.reason);
      // The manifest's directory comes back canonical (`/var` is
      // `/private/var` on macOS), so the two are compared resolved.
      expect(openerCalls, hasLength(1));
      expect(
        File(openerCalls.single).resolveSymbolicLinksSync(),
        lint.resolveSymbolicLinksSync(),
      );
    });

    // The opener swaps a manifest for its project itself, so a manifest
    // that names another manifest would be swapped a second time, past the
    // check. MUTATION: deleting the `isManifestPath(project)` refusal in
    // `openCxpProject` makes this red.
    test('a design manifest that names another manifest is refused', () async {
      final nested = Directory(p.join(never.path, 'nested'))..createSync();
      manifest(nested, 'nested.lintcrux');
      project(nested, 'nested.lintcrux');
      final design = manifest(never, 'nested/design.crux-project');
      final container = boot();
      final ack = await ask(container, hint: design.path);
      expect(ack.honored, isFalse);
      expect(ack.reason, 'the design manifest names another manifest');
      expect(openerCalls, isEmpty);
    });

    group('over a socket, through the server the lifecycle builds', () {
      Future<LocalCxpClient> connect(ProviderContainer container) async {
        final state = await container.read(cxpServerLifecycleProvider.future);
        expect(state.running, isTrue);
        final client = LocalCxpClient(
          selfIdentity: const PeerIdentity(
            peerId: 'open-artifact-test',
            productName: 'vscode',
            productVersion: '0.0.0-test',
          ),
        );
        await client.connect(
          host: '127.0.0.1',
          port: state.boundPort!,
          token: cxpProcessAuthToken,
        );
        addTearDown(client.dispose);
        return client;
      }

      Future<RequestOpenArtifactAck> send(
        LocalCxpClient client,
        String hint,
      ) async {
        final reply = client.inbound.firstWhere(
          (m) => m.message is RequestOpenArtifactAck,
        );
        client.send(
          RequestOpenArtifact(
            designId: 'unrecorded',
            artifactKind: kCxpLintcruxSourceKind,
            path: hint,
          ),
        );
        return (await reply.timeout(const Duration(seconds: 5))).message
            as RequestOpenArtifactAck;
      }

      // `LocalCxpServer` screens the hint on the wire before the handler
      // sees it, and a rooted screen there strips the hint for a project
      // never opened. No record is written, so the hint is all the handler
      // has. MUTATION: handing `LintCruxCxpServer` the rooted
      // `cxpPathContainmentProvider` in `CxpServerLifecycle.build` makes this
      // red.
      test('the hint for a project never opened crosses the wire, and it is '
          'opened', () async {
        final file = project(never, 'never.lintcrux');
        final client = await connect(boot());
        final ack = await send(client, file.path);
        expect(ack.honored, isTrue, reason: ack.reason);
        expect(openerCalls, <String>[file.path]);
      });

      // The wire screen is the floor too, and it judges the exact string, so
      // a padded hint is stripped before the handler sees it (a refused hint
      // is simply no fallback, CXP §9.10). With nothing recorded, the
      // request is declined for want of a record, which is how this tells
      // the wire's refusal from the handler's. MUTATION: handing
      // `LintCruxCxpServer` a containment that admits padded paths in
      // `CxpServerLifecycle.build` lets the hint through to the handler,
      // which refuses it with a different reason, and this goes red.
      test('a padded hint is stripped on the wire, and the request is '
          'declined', () async {
        project(never, 'padded.lintcrux');
        final trailing = project(never, 'padded.lintcrux ').path;
        final client = await connect(boot());
        final ack = await send(client, trailing);
        expect(ack.honored, isFalse);
        expect(
          ack.reason,
          'No source artifact recorded for design "unrecorded".',
        );
        expect(openerCalls, isEmpty);
      });
    });
  });

  // The `crux.design_id` fallback keeps the roots: a peer attaches the id to
  // a cross-probe, and the record it selects would be opened without the
  // user asking for that project. A rule highlight that misses in the
  // (empty) violation store takes it.
  group('the crux.design_id fallback', () {
    Future<RequestHighlightAck> probe(
      ProviderContainer container,
      String designId,
    ) async {
      final rulePath = LintCruxNameResolver.encodeViolationAsRulePath(
        _violation(),
      )!;
      final result = await container
          .read(cxpRequestHandlerProvider)
          .dispatch(
            _inbound(
              RequestHighlight(
                element: ElementId(kind: ElementKind.rule, path: rulePath),
                metadata: <String, Object?>{cxpDesignIdMetadataKey: designId},
              ),
            ),
          );
      return result.ack as RequestHighlightAck;
    }

    test('opens a project inside the opened projects', () async {
      final file = project(opened, 'sibling.lintcrux');
      await record('d-in', file.path);
      final container = boot();
      final ack = await probe(container, 'd-in');
      expect(ack.honored, isTrue, reason: ack.reason);
      expect(openerCalls, <String>[file.path]);
    });

    // MUTATION: replacing the rooted rule with the floor
    // (`const CxpPathContainment()`) in `cxpPathContainmentProvider` makes
    // this red.
    test('refuses a project never opened in this installation', () async {
      final file = project(never, 'never.lintcrux');
      await record('d-never', file.path);
      final container = boot();
      final ack = await probe(container, 'd-never');
      expect(ack.honored, isFalse);
      expect(openerCalls, isEmpty);
    });

    // The swap is judged under the fallback's own rule too: a manifest
    // inside the opened projects may name a lint project outside them, and
    // the opener used to swap it past the check. MUTATION: deleting the
    // `refuse(project)` re-check in `openCxpProject` makes this red.
    test('refuses a manifest inside the opened projects that names a project '
        'outside them', () async {
      final outside = project(never, 'elsewhere.lintcrux');
      final design = manifest(opened, outside.path);
      await record('d-manifest', design.path);
      final container = boot();
      final ack = await probe(container, 'd-manifest');
      expect(ack.honored, isFalse);
      expect(openerCalls, isEmpty);
    });

    // The store applies the rule to what it resolves, before any check of
    // the value about to be opened. MUTATION: dropping `containment:` from
    // `cxpWorkspaceStoreProvider` makes this red.
    test('the production store drops a record outside the opened '
        'projects', () async {
      final inside = project(opened, 'kept.lintcrux');
      final outside = project(never, 'dropped.lintcrux');
      await record('d-kept', inside.path);
      await record('d-dropped', outside.path);
      final container = ProviderContainer(
        overrides: <Override>[
          ...telemetryDeclinedOverrides(),
          cxpProjectOpenHandleProvider.overrideWithValue(
            CxpProjectOpenHandle()
              ..projectPaths = (() => <String>[
                p.join(opened.path, 'opened.lintcrux'),
              ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      // The rule the production store carries, over this test's records.
      final production = container.read(cxpWorkspaceStoreProvider);
      final store = CxpWorkspaceStore(
        workspaceDirectory: storeDir.path,
        ttl: production.ttl,
        containment: production.containment,
      );
      expect(
        store.resolveArtifact('d-kept', kCxpLintcruxSourceKind)?.path,
        inside.path,
      );
      expect(
        store.resolveArtifact('d-dropped', kCxpLintcruxSourceKind),
        isNull,
      );
    });
  });
}

/// A violation the rule highlight names; the store never holds it, so the
/// highlight misses and takes the workspace fallback.
Violation _violation() => const Violation(
  engineId: 'verilator',
  ruleId: 'verilator/UNUSEDSIGNAL',
  severity: Severity.warning,
  message: 'unused',
  location: SourceLocation(file: '/proj/cpu.sv', line: 42, column: 7),
);

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
    productName: 'vscode',
    productVersion: '0.0.0-test',
  ),
);

/// CXP on (the default), bound to an ephemeral port so the test never
/// collides with a running LintCrux on the default one.
class _CxpOnEphemeralPort extends AppSettingsNotifier {
  @override
  AppSettings build() => const AppSettings(cxpServerPort: 0);
}

/// Deletes [dir], tolerating a server that is still removing its manifest
/// from it.
void _deleteQuietly(Directory dir) {
  try {
    dir.deleteSync(recursive: true);
  } on FileSystemException {
    // Best effort.
  }
}
