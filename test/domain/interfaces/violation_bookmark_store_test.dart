// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/interfaces/violation_bookmark_store.dart';
import 'package:lintcrux/domain/models/bookmarked_violation.dart';

void main() {
  group('NoopViolationBookmarkStore', () {
    const store = NoopViolationBookmarkStore();

    test('listAll returns empty list', () async {
      final bookmarks = await store.listAll();
      expect(bookmarks, isEmpty);
    });

    test('lookupByFingerprint returns null', () async {
      final hit = await store.lookupByFingerprint('any_fp');
      expect(hit, isNull);
    });

    test('addOrUpdate is silent no-op', () async {
      // Must not throw — the bookmark feature is Pro; activating the
      // store on open-core should not surface an exception.
      await store.addOrUpdate(
        BookmarkedViolation(
          id: 'x',
          fingerprint: 'fp',
          ruleId: 'r/x',
          filePath: '/p/a.sv',
          lineNumber: 1,
          snippet: 's',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      // listAll still empty afterwards.
      expect(await store.listAll(), isEmpty);
    });

    test('remove is silent no-op', () async {
      await store.remove('any_id'); // must not throw
    });

    test('changed stream is empty', () async {
      final events = await store.changed.toList();
      expect(events, isEmpty);
    });
  });
}
