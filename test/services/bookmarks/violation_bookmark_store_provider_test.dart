// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/interfaces/violation_bookmark_store.dart';
import 'package:lintcrux/domain/models/baseline_violation.dart';
import 'package:lintcrux/domain/models/bookmarked_violation.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/services/bookmarks/json_file_violation_bookmark_store.dart';
import 'package:lintcrux/services/bookmarks/violation_bookmark_store_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lintcrux_bookmark_provider_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  ProviderContainer withProject(String rootPath) {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(currentProjectProvider.notifier)
        .load(LintProject(name: 'soc', rootPath: rootPath));
    return container;
  }

  /// The store's initial load is fire-and-forget; wait for it to settle.
  Future<List<BookmarkedViolation>> loaded(
    ViolationBookmarkStore store,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    var all = await store.listAll();
    while (all.isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      all = await store.listAll();
    }
    return all;
  }

  BookmarkedViolation bookmark({
    required String fingerprint,
    required String filePath,
    String? note,
  }) => BookmarkedViolation(
    id: 'bm-1',
    fingerprint: fingerprint,
    ruleId: 'verilator/UNUSEDSIGNAL',
    filePath: filePath,
    lineNumber: 10,
    snippet: 'unused signal foo',
    createdAt: DateTime.utc(2026, 5, 25, 12),
    updatedAt: DateTime.utc(2026, 5, 25, 12),
    note: note,
    color: '#FF9800',
    lastSeenRunId: 'run-7',
  );

  test('the bookmark file name', () {
    expect(kViolationBookmarksFileName, '.lintcrux-bookmarks.json');
  });

  test('no project: the no-op store', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(violationBookmarkStoreProvider),
      isA<NoopViolationBookmarkStore>(),
    );
  });

  test('a project with an empty root: the no-op store', () {
    final container = withProject('');
    expect(
      container.read(violationBookmarkStoreProvider),
      isA<NoopViolationBookmarkStore>(),
    );
  });

  test('a project: a JSON store over <root>/.lintcrux-bookmarks.json', () {
    final container = withProject(tmp.path);
    final store = container.read(violationBookmarkStoreProvider);
    expect(store, isA<JsonFileViolationBookmarkStore>());
    store as JsonFileViolationBookmarkStore;
    expect(
      p.equals(store.file.path, p.join(tmp.path, '.lintcrux-bookmarks.json')),
      isTrue,
    );
    expect(store.projectRoot, tmp.path);
  });

  test('closing the project returns to the no-op store', () {
    final container = withProject(tmp.path);
    expect(
      container.read(violationBookmarkStoreProvider),
      isA<JsonFileViolationBookmarkStore>(),
    );
    container.read(currentProjectProvider.notifier).clear();
    expect(
      container.read(violationBookmarkStoreProvider),
      isA<NoopViolationBookmarkStore>(),
    );
  });

  group('existing bookmark files keep loading', () {
    test('a version 2 file loads unchanged', () async {
      final filePath = p.join(tmp.path, 'rtl', 'a.sv');
      final fingerprint = BaselineFingerprint.forProject(
        ruleId: 'verilator/UNUSEDSIGNAL',
        filePath: filePath,
        message: 'unused signal foo',
        projectRoot: tmp.path,
      );
      final saved = bookmark(
        fingerprint: fingerprint,
        filePath: filePath,
        note: 'check after the reset rework',
      );
      File(p.join(tmp.path, '.lintcrux-bookmarks.json')).writeAsStringSync(
        jsonEncode(<String, Object?>{
          'version': 2,
          'bookmarks': <Object?>[saved.toJson()],
        }),
      );

      final container = withProject(tmp.path);
      final store = container.read(violationBookmarkStoreProvider);
      final all = await loaded(store);

      expect(all, hasLength(1));
      final bm = all.single;
      expect(bm.id, 'bm-1');
      expect(bm.fingerprint, fingerprint);
      expect(bm.note, 'check after the reset rework');
      expect(bm.color, '#FF9800');
      expect(bm.lastSeenRunId, 'run-7');
      expect(bm.createdAt, DateTime.utc(2026, 5, 25, 12));
      expect((await store.lookupByFingerprint(fingerprint))?.id, 'bm-1');
    });

    test('a version 1 file loads and matches this checkout', () async {
      // Version 1 hashed the absolute path of the checkout that wrote it;
      // the upgrade rehashes it root-relative.
      final absolute = p.join(tmp.path, 'rtl', 'a.sv');
      final legacy = bookmark(
        fingerprint: BaselineFingerprint.compute(
          ruleId: 'verilator/UNUSEDSIGNAL',
          filePath: absolute,
          message: 'unused signal foo',
        ),
        filePath: absolute,
      ).toJson()..['version'] = 1;
      File(p.join(tmp.path, '.lintcrux-bookmarks.json')).writeAsStringSync(
        jsonEncode(<String, Object?>{
          'version': 1,
          'bookmarks': <Object?>[legacy],
        }),
      );

      final container = withProject(tmp.path);
      final store = container.read(violationBookmarkStoreProvider);
      final all = await loaded(store);

      expect(all, hasLength(1));
      expect(all.single.id, 'bm-1');
      expect(all.single.lastSeenRunId, 'run-7');
      final here = BaselineFingerprint.forProject(
        ruleId: 'verilator/UNUSEDSIGNAL',
        filePath: p.join(tmp.path, 'rtl', 'a.sv'),
        message: 'unused signal foo',
        projectRoot: tmp.path,
      );
      expect((await store.lookupByFingerprint(here))?.id, 'bm-1');
    });
  });
}
