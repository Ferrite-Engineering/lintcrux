// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/interfaces/violation_bookmark_store.dart';
import 'package:lintcrux/domain/models/baseline_violation.dart';
import 'package:lintcrux/domain/models/bookmarked_violation.dart';
import 'package:lintcrux/features/bookmarks/screens/bookmark_panel.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/bookmarks/bookmark_freshness.dart';
import 'package:lintcrux/services/bookmarks/violation_bookmark_store_provider.dart';

BookmarkedViolation _bm({
  required String id,
  required String file,
  required int line,
  String? note,
  String? color,
  String? lastSeenRunId,
}) {
  return BookmarkedViolation(
    id: id,
    fingerprint: BaselineFingerprint.compute(
      ruleId: 'verilator/UNUSEDSIGNAL',
      filePath: file,
      message: 'unused $id',
    ),
    ruleId: 'verilator/UNUSEDSIGNAL',
    filePath: file,
    lineNumber: line,
    snippet: 'unused $id',
    note: note,
    color: color,
    lastSeenRunId: lastSeenRunId,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

class _FakeStore implements ViolationBookmarkStore {
  _FakeStore(List<BookmarkedViolation> initial) {
    _items.addAll(initial);
  }

  final List<BookmarkedViolation> _items = [];
  final StreamController<void> _events = StreamController<void>.broadcast();

  bool removeCalled = false;

  @override
  Future<List<BookmarkedViolation>> listAll() async =>
      List.unmodifiable(_items);

  @override
  Future<BookmarkedViolation?> lookupByFingerprint(String fingerprint) async {
    for (final bm in _items) {
      if (bm.fingerprint == fingerprint) return bm;
    }
    return null;
  }

  @override
  Future<void> addOrUpdate(BookmarkedViolation bookmark) async {
    _items
      ..removeWhere((b) => b.id == bookmark.id)
      ..add(bookmark);
    _events.add(null);
  }

  @override
  Future<void> remove(String bookmarkId) async {
    removeCalled = true;
    _items.removeWhere((b) => b.id == bookmarkId);
    _events.add(null);
  }

  @override
  Stream<void> get changed => _events.stream;
}

/// Pins [bookmarkFreshnessProvider] to a fixed latest run id.
class _FixedRunId extends BookmarkFreshnessNotifier {
  _FixedRunId(this.runId);

  final String runId;

  @override
  String? build() => runId;
}

Future<void> _pump(
  WidgetTester tester, {
  required List<Override> overrides,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          L10N.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10N.supportedLocales,
        home: const Scaffold(body: BookmarkPanel()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  group('BookmarkPanel', () {
    testWidgets('empty state shows the empty-canvas hint', (tester) async {
      await _pump(
        tester,
        overrides: [
          violationBookmarkStoreProvider.overrideWithValue(_FakeStore([])),
        ],
      );
      expect(
        find.text(
          'Click the bookmark icon on any violation row to keep '
          'track of it across runs.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders one row per bookmark grouped by file', (tester) async {
      await _pump(
        tester,
        overrides: [
          violationBookmarkStoreProvider.overrideWithValue(
            _FakeStore([
              _bm(id: 'b1', file: '/a.sv', line: 12),
              _bm(id: 'b2', file: '/a.sv', line: 34),
              _bm(id: 'b3', file: '/b.sv', line: 5),
            ]),
          ),
        ],
      );
      expect(find.byKey(const ValueKey('bookmarkPanelRow-b1')), findsOneWidget);
      expect(find.byKey(const ValueKey('bookmarkPanelRow-b2')), findsOneWidget);
      expect(find.byKey(const ValueKey('bookmarkPanelRow-b3')), findsOneWidget);
      // File headers visible.
      expect(find.text('/a.sv'), findsOneWidget);
      expect(find.text('/b.sv'), findsOneWidget);
    });

    testWidgets(
      'stale filter narrows to bookmarks that lag latest run',
      (tester) async {
        await _pump(
          tester,
          overrides: [
            violationBookmarkStoreProvider.overrideWithValue(
              _FakeStore([
                _bm(id: 'fresh', file: '/a.sv', line: 1, lastSeenRunId: 'now'),
                _bm(id: 'stale', file: '/b.sv', line: 1, lastSeenRunId: 'old'),
              ]),
            ),
            bookmarkFreshnessProvider.overrideWith(() => _FixedRunId('now')),
          ],
        );
        await tester.tap(
          find.byKey(const ValueKey('bookmarkPanelFilterStale')),
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('bookmarkPanelRow-fresh')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('bookmarkPanelRow-stale')),
          findsOneWidget,
        );
      },
    );

    testWidgets('search narrows to substring match', (tester) async {
      await _pump(
        tester,
        overrides: [
          violationBookmarkStoreProvider.overrideWithValue(
            _FakeStore([
              _bm(id: 'a', file: '/match.sv', line: 1),
              _bm(id: 'b', file: '/other.sv', line: 1),
            ]),
          ),
        ],
      );
      await tester.enterText(
        find.byKey(const ValueKey('bookmarkPanelSearch')),
        'match',
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('bookmarkPanelRow-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('bookmarkPanelRow-b')), findsNothing);
    });

    testWidgets(
      'remove action shows confirm dialog then deletes',
      (tester) async {
        final store = _FakeStore([_bm(id: 'a', file: '/a.sv', line: 1)]);
        await _pump(
          tester,
          overrides: [
            violationBookmarkStoreProvider.overrideWithValue(store),
          ],
        );
        await tester.tap(find.byKey(const ValueKey('bookmarkPanelRowMenu-a')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove bookmark'));
        await tester.pumpAndSettle();
        // Confirm dialog visible.
        expect(find.text('Remove bookmark?'), findsOneWidget);
        await tester.tap(find.text('Remove'));
        await tester.pumpAndSettle();
        expect(store.removeCalled, isTrue);
      },
    );

    group('locale sweep', () {
      for (final loc in const [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('ja'),
        Locale('ko'),
      ]) {
        testWidgets(
          'renders without exception in ${loc.languageCode}',
          (tester) async {
            await _pump(
              tester,
              locale: loc,
              overrides: [
                violationBookmarkStoreProvider.overrideWithValue(
                  _FakeStore([
                    _bm(id: 'a', file: '/a.sv', line: 1, note: 'hello'),
                  ]),
                ),
              ],
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    });
  });
}
