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
import 'package:lintcrux/features/bookmarks/providers/bookmark_openers.dart';
import 'package:lintcrux/features/bookmarks/widgets/bookmark_count_badge.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/bookmarks/violation_bookmark_store_provider.dart';

BookmarkedViolation _bm(int n) {
  return BookmarkedViolation(
    id: 'bm-$n',
    fingerprint: BaselineFingerprint.compute(
      ruleId: 'verilator/UNUSEDSIGNAL',
      filePath: '/a$n.sv',
      message: 'unused $n',
    ),
    ruleId: 'verilator/UNUSEDSIGNAL',
    filePath: '/a$n.sv',
    lineNumber: 1,
    snippet: 'unused $n',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

class _FakeStore implements ViolationBookmarkStore {
  _FakeStore({List<BookmarkedViolation> initial = const []}) {
    _items.addAll(initial);
  }

  final List<BookmarkedViolation> _items = [];
  final StreamController<void> _events = StreamController<void>.broadcast();

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
    _items.removeWhere((b) => b.id == bookmarkId);
    _events.add(null);
  }

  @override
  Stream<void> get changed => _events.stream;
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
        home: const Scaffold(body: BookmarkCountBadge()),
      ),
    ),
  );
  // Settle the StreamProvider.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  group('BookmarkCountBadge', () {
    testWidgets('renders the count text', (tester) async {
      await _pump(
        tester,
        overrides: [
          violationBookmarkStoreProvider.overrideWithValue(
            _FakeStore(initial: [_bm(1), _bm(2), _bm(3)]),
          ),
        ],
      );
      expect(
        find.byKey(const ValueKey('bookmarkCountBadgeText')),
        findsOneWidget,
      );
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('shows zero when no bookmarks exist', (tester) async {
      await _pump(
        tester,
        overrides: [
          violationBookmarkStoreProvider.overrideWithValue(_FakeStore()),
        ],
      );
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('tap dispatches the panel opener', (tester) async {
      var opened = false;
      await _pump(
        tester,
        overrides: [
          violationBookmarkStoreProvider.overrideWithValue(_FakeStore()),
          bookmarkPanelOpenerProvider.overrideWithValue((_) {
            opened = true;
          }),
        ],
      );
      await tester.tap(find.byKey(const ValueKey('bookmarkCountBadgeText')));
      await tester.pump();
      expect(opened, isTrue);
    });

    group('locale sweep', () {
      for (final loc in const [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('ja'),
        Locale('ko'),
      ]) {
        testWidgets('renders without exception in ${loc.languageCode}', (
          tester,
        ) async {
          await _pump(
            tester,
            locale: loc,
            overrides: [
              violationBookmarkStoreProvider.overrideWithValue(
                _FakeStore(initial: [_bm(1)]),
              ),
            ],
          );
          expect(tester.takeException(), isNull);
        });
      }
    });
  });
}
