// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/baseline_violation.dart';
import 'package:lintcrux/domain/models/bookmarked_violation.dart';
import 'package:lintcrux/services/bookmarks/json_file_violation_bookmark_store.dart';

BookmarkedViolation _bm({
  String id = 'bm_1',
  String fingerprint = 'fp_1',
  String ruleId = 'verilator/UNUSED',
  String filePath = '/p/a.sv',
  int line = 10,
  String snippet = 'Signal is unused',
  String? note,
  String? color,
  String? lastSeenRunId,
}) {
  final ts = DateTime.utc(2026, 5, 25, 12);
  return BookmarkedViolation(
    id: id,
    fingerprint: fingerprint,
    ruleId: ruleId,
    filePath: filePath,
    lineNumber: line,
    snippet: snippet,
    createdAt: ts,
    updatedAt: ts,
    note: note,
    color: color,
    lastSeenRunId: lastSeenRunId,
  );
}

void main() {
  group('JsonFileViolationBookmarkStore', () {
    late Directory tmp;
    late File file;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('lintcrux_bookmarks_');
      file = File('${tmp.path}/.lintcrux-bookmarks.json');
    });

    tearDown(() async {
      if (tmp.existsSync()) {
        await tmp.delete(recursive: true);
      }
    });

    test('listAll on a missing file returns empty', () async {
      final store = JsonFileViolationBookmarkStore(file, projectRoot: tmp.path);
      addTearDown(store.dispose);
      await store.load();
      expect(await store.listAll(), isEmpty);
    });

    test('addOrUpdate writes a new bookmark and exposes it', () async {
      final store = JsonFileViolationBookmarkStore(file, projectRoot: tmp.path);
      addTearDown(store.dispose);
      await store.load();
      await store.addOrUpdate(_bm());
      final all = await store.listAll();
      expect(all.length, equals(1));
      expect(file.existsSync(), isTrue);
    });

    test('lookupByFingerprint hits in O(1) after add', () async {
      final store = JsonFileViolationBookmarkStore(file, projectRoot: tmp.path);
      addTearDown(store.dispose);
      await store.load();
      await store.addOrUpdate(_bm(fingerprint: 'fp_xyz'));
      final found = await store.lookupByFingerprint('fp_xyz');
      expect(found, isNotNull);
      expect(found?.id, equals('bm_1'));
      expect(await store.lookupByFingerprint('fp_unknown'), isNull);
    });

    test(
      'addOrUpdate with same id (update path) replaces in place',
      () async {
        final store = JsonFileViolationBookmarkStore(
          file,
          projectRoot: tmp.path,
        );
        addTearDown(store.dispose);
        await store.load();
        await store.addOrUpdate(_bm(note: 'original'));
        await store.addOrUpdate(_bm(note: 'updated'));
        final all = await store.listAll();
        expect(all.length, equals(1));
        expect(all.single.note, equals('updated'));
      },
    );

    test(
      'addOrUpdate rejects fingerprint collision from a different id',
      () async {
        final store = JsonFileViolationBookmarkStore(
          file,
          projectRoot: tmp.path,
        );
        addTearDown(store.dispose);
        await store.load();
        await store.addOrUpdate(_bm(id: 'bm_a', fingerprint: 'fp_shared'));
        expect(
          () => store.addOrUpdate(
            _bm(id: 'bm_b', fingerprint: 'fp_shared'),
          ),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test(
      'remove deletes the bookmark and clears the fingerprint index',
      () async {
        final store = JsonFileViolationBookmarkStore(
          file,
          projectRoot: tmp.path,
        );
        addTearDown(store.dispose);
        await store.load();
        await store.addOrUpdate(_bm(fingerprint: 'fp_x'));
        await store.remove('bm_1');
        expect(await store.listAll(), isEmpty);
        expect(await store.lookupByFingerprint('fp_x'), isNull);
      },
    );

    test('remove on unknown id is a silent no-op', () async {
      final store = JsonFileViolationBookmarkStore(file, projectRoot: tmp.path);
      addTearDown(store.dispose);
      await store.load();
      await store.remove('unknown'); // must not throw
    });

    test('round-trip: save, dispose, reload preserves bookmarks', () async {
      final store1 = JsonFileViolationBookmarkStore(
        file,
        projectRoot: tmp.path,
      );
      await store1.load();
      await store1.addOrUpdate(
        _bm(
          note: 'Persisted',
          color: '#FF0000',
          lastSeenRunId: 'run-1',
        ),
      );
      await store1.dispose();

      final store2 = JsonFileViolationBookmarkStore(
        file,
        projectRoot: tmp.path,
      );
      addTearDown(store2.dispose);
      await store2.load();
      final all = await store2.listAll();
      expect(all.length, equals(1));
      expect(all.single.note, equals('Persisted'));
      expect(all.single.color, equals('#FF0000'));
      expect(all.single.lastSeenRunId, equals('run-1'));
    });

    test('rejects file with unknown schema version', () async {
      file.writeAsStringSync(
        jsonEncode(<String, Object?>{
          'version': 999,
          'bookmarks': <Object?>[],
        }),
      );
      final store = JsonFileViolationBookmarkStore(file, projectRoot: tmp.path);
      addTearDown(store.dispose);
      expect(store.load, throwsA(isA<FormatException>()));
    });

    test(
      'a version 1 file is read and its fingerprints made root-relative',
      () async {
        // Written by a build that hashed the absolute path, in a checkout
        // somewhere else: the bookmark must match this checkout's findings.
        final legacy = _bm(
          fingerprint: BaselineFingerprint.compute(
            ruleId: 'verilator/UNUSED',
            filePath: '/Users/alice/soc/rtl/a.sv',
            message: 'Signal is unused',
          ),
          filePath: '/Users/alice/soc/rtl/a.sv',
        ).toJson()..['version'] = 1;
        file.writeAsStringSync(
          jsonEncode(<String, Object?>{
            'version': 1,
            'bookmarks': <Object?>[legacy],
          }),
        );
        final store = JsonFileViolationBookmarkStore(
          file,
          projectRoot: '/Users/alice/soc',
        );
        addTearDown(store.dispose);
        await store.load();

        final here = BaselineFingerprint.forProject(
          ruleId: 'verilator/UNUSED',
          filePath: '${tmp.path}/rtl/a.sv',
          message: 'Signal is unused',
          projectRoot: tmp.path,
        );
        final found = await store.lookupByFingerprint(here);
        expect(found?.id, 'bm_1');
        expect(found?.version, BookmarkedViolation.currentVersion);

        await store.addOrUpdate(found!.copyWith(note: 'rewritten'));
        final written = jsonDecode(file.readAsStringSync()) as Map;
        expect(
          written['version'],
          JsonFileViolationBookmarkStore.currentVersion,
        );
      },
    );

    test('rejects file missing version field', () async {
      file.writeAsStringSync(
        jsonEncode(<String, Object?>{
          'bookmarks': <Object?>[],
        }),
      );
      final store = JsonFileViolationBookmarkStore(file, projectRoot: tmp.path);
      addTearDown(store.dispose);
      expect(store.load, throwsA(isA<FormatException>()));
    });

    // A malformed entry partway through used to leave the bookmarks before it
    // loaded; the stale-detection write after the next lint run then deleted
    // every bookmark after it from the committed file, with no user action.
    test('a file that cannot be read is never written over, not even by '
        'stale detection', () async {
      final bad = Map<String, Object?>.of(_bm(id: 'bm_2').toJson())
        ..remove('createdAt');
      final original = jsonEncode({
        'version': JsonFileViolationBookmarkStore.currentVersion,
        'bookmarks': [_bm().toJson(), bad, _bm(id: 'bm_3').toJson()],
      });
      await file.writeAsString(original);
      final store = JsonFileViolationBookmarkStore(file, projectRoot: tmp.path);
      addTearDown(store.dispose);

      await expectLater(store.load(), throwsA(anything));
      expect(store.loadError, isNotNull);
      expect(await store.listAll(), isEmpty, reason: 'nothing half-loaded');

      await store.updateLastSeenForRun(
        runId: 'r9',
        firingFingerprints: {_bm().fingerprint},
      );
      await expectLater(
        store.addOrUpdate(_bm(id: 'bm_new', fingerprint: 'fp_new')),
        throwsA(isA<StateError>()),
      );
      await expectLater(store.remove('bm_1'), throwsA(isA<StateError>()));
      expect(await file.readAsString(), original);
    });

    test('a completed load notifies listeners', () async {
      await file.writeAsString(
        jsonEncode({
          'version': JsonFileViolationBookmarkStore.currentVersion,
          'bookmarks': [_bm().toJson()],
        }),
      );
      final store = JsonFileViolationBookmarkStore(file, projectRoot: tmp.path);
      addTearDown(store.dispose);
      var notified = 0;
      final sub = store.changed.listen((_) => notified++);
      addTearDown(sub.cancel);

      await store.load();
      await Future<void>.delayed(Duration.zero);

      expect(notified, 1);
    });

    test('changed stream fires on add + remove', () async {
      final store = JsonFileViolationBookmarkStore(file, projectRoot: tmp.path);
      addTearDown(store.dispose);
      await store.load();
      final events = <void>[];
      final sub = store.changed.listen(events.add);
      await store.addOrUpdate(_bm());
      await store.remove('bm_1');
      await Future<void>.delayed(Duration.zero);
      expect(events.length, greaterThanOrEqualTo(2));
      await sub.cancel();
    });

    test(
      'updateLastSeenForRun refreshes lastSeenRunId on firing bookmarks',
      () async {
        final store = JsonFileViolationBookmarkStore(
          file,
          projectRoot: tmp.path,
        );
        addTearDown(store.dispose);
        await store.load();
        await store.addOrUpdate(_bm(id: 'bm_a', fingerprint: 'fp_a'));
        await store.addOrUpdate(_bm(id: 'bm_b', fingerprint: 'fp_b'));
        // Only bm_a's fingerprint fires in the run.
        await store.updateLastSeenForRun(
          runId: 'run-99',
          firingFingerprints: {'fp_a'},
        );
        final all = await store.listAll();
        final byId = {for (final b in all) b.id: b};
        expect(byId['bm_a']?.lastSeenRunId, equals('run-99'));
        expect(byId['bm_b']?.lastSeenRunId, isNull);
      },
    );

    test(
      'updateLastSeenForRun does NOT touch updatedAt',
      () async {
        final store = JsonFileViolationBookmarkStore(
          file,
          projectRoot: tmp.path,
        );
        addTearDown(store.dispose);
        await store.load();
        final original = _bm(fingerprint: 'fp_a');
        await store.addOrUpdate(original);
        await store.updateLastSeenForRun(
          runId: 'run-99',
          firingFingerprints: {'fp_a'},
        );
        final updated = (await store.listAll()).single;
        expect(updated.updatedAt, equals(original.updatedAt));
        expect(updated.lastSeenRunId, equals('run-99'));
      },
    );

    test(
      'updateLastSeenForRun is a no-op when nothing changes',
      () async {
        final store = JsonFileViolationBookmarkStore(
          file,
          projectRoot: tmp.path,
        );
        addTearDown(store.dispose);
        await store.load();
        await store.addOrUpdate(
          _bm(fingerprint: 'fp_a', lastSeenRunId: 'run-99'),
        );
        var events = 0;
        final sub = store.changed.listen((_) => events++);
        // Same fingerprint firing with the same runId — no mutation.
        await store.updateLastSeenForRun(
          runId: 'run-99',
          firingFingerprints: {'fp_a'},
        );
        await Future<void>.delayed(Duration.zero);
        expect(events, equals(0));
        await sub.cancel();
      },
    );

    test(
      'atomic write leaves no .tmp file behind on success',
      () async {
        final store = JsonFileViolationBookmarkStore(
          file,
          projectRoot: tmp.path,
        );
        addTearDown(store.dispose);
        await store.load();
        await store.addOrUpdate(_bm());
        expect(File('${file.path}.tmp').existsSync(), isFalse);
      },
    );
  });
}
