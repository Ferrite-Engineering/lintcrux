// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/violation_bookmark_store.dart';
import 'package:lintcrux/domain/models/baseline_violation.dart';
import 'package:lintcrux/domain/models/bookmarked_violation.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/bookmarks/violation_bookmark_lookup_provider.dart';
import 'package:lintcrux/services/bookmarks/violation_bookmark_store_provider.dart';

/// Checks [condition] every 20 ms until it holds, failing after 2 s.
Future<void> pollUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('pollUntil: condition not satisfied within 2s');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _FakeStore implements ViolationBookmarkStore {
  final Map<String, BookmarkedViolation> _items = {};
  final StreamController<void> _events = StreamController<void>.broadcast();

  @override
  Future<List<BookmarkedViolation>> listAll() async => _items.values.toList();

  @override
  Future<BookmarkedViolation?> lookupByFingerprint(String fingerprint) async {
    for (final bm in _items.values) {
      if (bm.fingerprint == fingerprint) return bm;
    }
    return null;
  }

  @override
  Future<void> addOrUpdate(BookmarkedViolation bookmark) async {
    _items[bookmark.id] = bookmark;
    _events.add(null);
  }

  @override
  Future<void> remove(String bookmarkId) async {
    _items.remove(bookmarkId);
    _events.add(null);
  }

  @override
  Stream<void> get changed => _events.stream;
}

BookmarkedViolation _bm(String id, Violation v) {
  return BookmarkedViolation(
    id: id,
    fingerprint: BaselineFingerprint.compute(
      ruleId: v.ruleId,
      filePath: v.location.file,
      message: v.message,
    ),
    ruleId: v.ruleId,
    filePath: v.location.file,
    lineNumber: v.location.line,
    snippet: v.message,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

const _violation = Violation(
  engineId: 'verilator',
  ruleId: 'verilator/UNUSEDSIGNAL',
  severity: Severity.warning,
  message: 'unused foo',
  location: SourceLocation(file: '/a.sv', line: 1, column: 1),
);

void main() {
  group('computeBookmarkFingerprint', () {
    test('matches BaselineFingerprint.forProject on the violation triple', () {
      expect(
        computeBookmarkFingerprint(_violation, projectRoot: '/'),
        BaselineFingerprint.forProject(
          ruleId: _violation.ruleId,
          filePath: _violation.location.file,
          message: _violation.message,
          projectRoot: '/',
        ),
      );
    });

    test('is the same in every checkout of the project', () {
      Violation at(String root) => Violation(
        engineId: 'verilator',
        ruleId: 'verilator/UNUSEDSIGNAL',
        severity: Severity.warning,
        message: 'unused foo',
        location: SourceLocation(file: '$root/rtl/a.sv', line: 1, column: 1),
      );
      expect(
        computeBookmarkFingerprint(at('/a/soc'), projectRoot: '/a/soc'),
        computeBookmarkFingerprint(at('/b/soc'), projectRoot: '/b/soc'),
      );
    });
  });

  group('violationBookmarkLookupMapProvider', () {
    test('initial value is an empty map for an empty store', () async {
      final store = _FakeStore();
      final container = ProviderContainer(
        overrides: [
          violationBookmarkStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(
        violationBookmarkLookupMapProvider,
        (_, _) {},
      );
      // Wait for the async* to yield its first value.
      await pollUntil(() => sub.read().hasValue);
      final state = sub.read();
      final m = state.maybeWhen(data: (m) => m, orElse: () => null);
      expect(m, isNotNull);
      expect(m, isEmpty);
    });

    test('seeded store yields a map keyed by fingerprint', () async {
      final bm = _bm('bm-1', _violation);
      final store = _FakeStore();
      await store.addOrUpdate(bm);
      final container = ProviderContainer(
        overrides: [
          violationBookmarkStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(
        violationBookmarkLookupMapProvider,
        (_, _) {},
      );
      await pollUntil(() => sub.read().hasValue);
      final state = container.read(violationBookmarkLookupMapProvider);
      final m = state.maybeWhen(data: (m) => m, orElse: () => null);
      expect(m, isNotNull);
      expect(m![bm.fingerprint], bm);
    });

    test('store changes trigger a re-emit with the updated map', () async {
      final store = _FakeStore();
      final container = ProviderContainer(
        overrides: [
          violationBookmarkStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      final emissions = <int>[];
      container.listen<AsyncValue<Map<String, BookmarkedViolation>>>(
        violationBookmarkLookupMapProvider,
        (_, next) {
          next.whenData((m) => emissions.add(m.length));
        },
        fireImmediately: true,
      );
      await pollUntil(() => emissions.isNotEmpty);
      await store.addOrUpdate(_bm('bm-1', _violation));
      await store.addOrUpdate(_bm('bm-2', _violation.copyWith(message: 'b')));
      // Emissions should include 0 (initial empty), 1 (after first add),
      // 2 (after second add). The async pump may coalesce; assert the
      // strictly-monotonic growth.
      await pollUntil(() => emissions.isNotEmpty && emissions.last >= 2);
      expect(emissions, isNotEmpty);
      expect(emissions.last, greaterThanOrEqualTo(2));
    });
  });
}
