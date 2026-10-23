// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:path/path.dart' as p;

// The `project` artifact kind (CXP 9.10.2): LintCrux publishes its project as
// `project`, never `source`, which names one HDL file. For one release a
// project still recorded as `source` is read too, and another product's record
// under the same design id is never handed to LintCrux to open.
//
// MUTATION: publishing with the legacy kind turns the publish case red;
// resolving `source` only, or `project` only, turns the matching resolution
// case red; dropping `accepts: isOpenableProjectPath` from either resolver
// opens the other product's file.

final Provider<Ref> _refProvider = Provider<Ref>((ref) => ref);

void main() {
  // Record times are real: the store prunes a record older than its TTL.
  final base = DateTime.now().millisecondsSinceEpoch;
  late Directory records;
  late Directory design;
  late CxpWorkspaceStore store;
  late ProviderContainer container;

  setUp(() {
    records = Directory.systemTemp.createTempSync('lintcrux_link_ws_');
    design = Directory.systemTemp.createTempSync('lintcrux_link_design_');
    store = CxpWorkspaceStore(workspaceDirectory: records.path);
    container = ProviderContainer(
      overrides: [cxpWorkspaceStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
  });

  tearDown(() {
    for (final dir in <Directory>[records, design]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  File write(String name) =>
      File(p.join(design.path, name))..writeAsStringSync('{}');

  String designId() => cxpDesignIdForPath(p.join(design.path, 'x'));

  Future<void> record(String kind, File file, {String producer = 'vscode'}) =>
      store.upsertArtifact(
        designId: designId(),
        kind: kind,
        path: file.path,
        producer: producer,
      );

  group('publishing', () {
    test('writes the project as kind project, with its basename and top '
        'module, and never as source, only while the server runs', () async {
      final file = write('uart.lintcrux');
      final project = LintProject(
        name: 'uart',
        rootPath: design.path,
        topModule: 'uart_top',
      );

      await publishLintcruxProjectArtifact(
        container.read(_refProvider),
        file.path,
        project,
      );
      expect(
        await store.resolveArtifactAsync(designId(), kCxpLintcruxProjectKind),
        isNull,
        reason: 'the CXP server is not running',
      );

      final running = ProviderContainer(
        parent: container,
        overrides: [
          _refProvider.overrideWith((ref) => ref),
          cruxCxpServerStatusProvider.overrideWithValue((
            running: true,
            port: 54325,
            problem: null,
          )),
        ],
      );
      addTearDown(running.dispose);
      await publishLintcruxProjectArtifact(
        running.read(_refProvider),
        file.path,
        project,
      );

      final artifact = await store.resolveArtifactAsync(
        cxpDesignIdForPath(file.path),
        kCxpLintcruxProjectKind,
      );
      expect(artifact?.path, file.path);
      expect(artifact?.producer, kLintcruxProducer);
      expect(artifact?.basename, 'uart.lintcrux');
      expect(artifact?.topModule, 'uart_top');
      expect(
        await store.resolveArtifactAsync(
          cxpDesignIdForPath(file.path),
          kCxpLintcruxLegacySourceKind,
        ),
        isNull,
        reason: 'never as source',
      );
    });

    test('the kinds are the ones CXP 9.10.2 names', () {
      expect(kCxpLintcruxProjectKind, 'project');
      expect(kCxpLintcruxLegacySourceKind, 'source');
    });
  });

  // The `crux.design_id` fallback and `request_open_artifact` read the same
  // records, the first under the rooted rule and the second under the floor.
  // Both go through the same two-kind read, so one table drives both.
  final resolvers = <String, Future<String?> Function(Ref, String)>{
    'the crux.design_id fallback': resolveLintcruxProjectArtifactPath,
    'request_open_artifact': resolveOpenArtifactProjectPath,
  };
  for (final entry in resolvers.entries) {
    group('resolving for ${entry.key}', () {
      Future<String?> resolve() =>
          entry.value(container.read(_refProvider), designId());

      test('a project record resolves', () async {
        final file = write('uart.lintcrux');
        await record(kCxpLintcruxProjectKind, file);
        expect(await resolve(), file.path);
      });

      test('a design manifest recorded as project resolves', () async {
        final file = write('uart.crux-project');
        await record(kCxpLintcruxProjectKind, file);
        expect(await resolve(), file.path);
      });

      test('a legacy source record still resolves', () async {
        final file = write('uart.lintcrux');
        await record(kCxpLintcruxLegacySourceKind, file);
        expect(await resolve(), file.path);
      });

      test('a project record wins over a newer legacy source record', () async {
        final project = write('current.lintcrux');
        final legacy = write('legacy.lintcrux');
        await store.upsertArtifact(
          designId: designId(),
          kind: kCxpLintcruxProjectKind,
          path: project.path,
          producer: 'lintcrux',
          ts: base - 4000,
        );
        await store.upsertArtifact(
          designId: designId(),
          kind: kCxpLintcruxLegacySourceKind,
          path: legacy.path,
          producer: 'lintcrux',
          ts: base - 3000,
        );
        expect(await resolve(), project.path);
      });

      test("another product's record under the same design id is never "
          'resolved, whatever its kind', () async {
        await record(kCxpLintcruxProjectKind, write('simcrux.yaml'));
        await record(kCxpLintcruxProjectKind, write('design.netcrux-project'));
        await record(kCxpLintcruxProjectKind, write('files.f'));
        await record(kCxpLintcruxLegacySourceKind, write('top.sv'));
        await record(kCxpLintcruxLegacySourceKind, write('top.vhd'));
        expect(await resolve(), isNull);
      });

      test(
        'our project is found beneath newer records of other products',
        () async {
          final mine = write('uart.lintcrux');
          await store.upsertArtifact(
            designId: designId(),
            kind: kCxpLintcruxProjectKind,
            path: mine.path,
            producer: 'lintcrux',
            ts: base - 4000,
          );
          await store.upsertArtifact(
            designId: designId(),
            kind: kCxpLintcruxProjectKind,
            path: write('simcrux.yaml').path,
            producer: 'simcrux',
            ts: base - 2000,
          );
          await store.upsertArtifact(
            designId: designId(),
            kind: kCxpLintcruxLegacySourceKind,
            path: write('top.sv').path,
            producer: 'vscode',
            ts: base - 1000,
          );
          expect(await resolve(), mine.path);
        },
      );

      test('a design with nothing recorded resolves to null', () async {
        expect(await resolve(), isNull);
      });
    });
  }
}
