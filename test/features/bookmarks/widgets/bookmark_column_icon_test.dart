// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/violation_bookmark_store.dart';
import 'package:lintcrux/domain/models/baseline_violation.dart';
import 'package:lintcrux/domain/models/bookmarked_violation.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/bookmarks/widgets/bookmark_column_icon.dart';
import 'package:lintcrux/features/bookmarks/widgets/bookmark_dialog.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/bookmarks/bookmark_freshness.dart';
import 'package:lintcrux/services/bookmarks/violation_bookmark_store_provider.dart';

import '../../../support/telemetry_test_store.dart';

const _violation = Violation(
  engineId: 'verilator',
  ruleId: 'verilator/UNUSEDSIGNAL',
  severity: Severity.warning,
  message: 'unused signal foo',
  location: SourceLocation(file: '/a.sv', line: 12, column: 1),
);

BookmarkedViolation _bookmark({
  String? color,
  String? lastSeenRunId,
}) {
  return BookmarkedViolation(
    id: 'bm-1',
    fingerprint: BaselineFingerprint.compute(
      ruleId: _violation.ruleId,
      filePath: _violation.location.file,
      message: _violation.message,
    ),
    ruleId: _violation.ruleId,
    filePath: _violation.location.file,
    lineNumber: _violation.location.line,
    snippet: _violation.message,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    color: color,
    lastSeenRunId: lastSeenRunId,
  );
}

class _FakeBookmarkStore implements ViolationBookmarkStore {
  _FakeBookmarkStore({List<BookmarkedViolation> initial = const []}) {
    for (final bm in initial) {
      _byId[bm.id] = bm;
      _byFingerprint[bm.fingerprint] = bm;
    }
  }

  final Map<String, BookmarkedViolation> _byId = {};
  final Map<String, BookmarkedViolation> _byFingerprint = {};
  final StreamController<void> _events = StreamController<void>.broadcast();

  bool removed = false;
  bool addedOrUpdated = false;
  BookmarkedViolation? lastAddedOrUpdated;

  @override
  Future<List<BookmarkedViolation>> listAll() async => _byId.values.toList();

  @override
  Future<BookmarkedViolation?> lookupByFingerprint(String fingerprint) async =>
      _byFingerprint[fingerprint];

  @override
  Future<void> addOrUpdate(BookmarkedViolation bookmark) async {
    addedOrUpdated = true;
    lastAddedOrUpdated = bookmark;
    final existing = _byId[bookmark.id];
    if (existing != null) _byFingerprint.remove(existing.fingerprint);
    _byId[bookmark.id] = bookmark;
    _byFingerprint[bookmark.fingerprint] = bookmark;
    _events.add(null);
  }

  @override
  Future<void> remove(String bookmarkId) async {
    removed = true;
    final existing = _byId.remove(bookmarkId);
    if (existing != null) _byFingerprint.remove(existing.fingerprint);
    _events.add(null);
  }

  @override
  Stream<void> get changed => _events.stream;
}

/// A store that behaves like `JsonFileViolationBookmarkStore` where it
/// matters here: it loads a snapshot of [disk] when created, and every write
/// replaces the whole of [disk] with its own snapshot. Writes still land
/// after [dispose], as the real store's do.
class _SnapshotStore implements ViolationBookmarkStore {
  _SnapshotStore(this.disk) : _mem = {...disk};

  final Map<String, BookmarkedViolation> disk;
  final Map<String, BookmarkedViolation> _mem;
  final StreamController<void> _events = StreamController<void>.broadcast();

  void _write() {
    disk
      ..clear()
      ..addAll(_mem);
    if (!_events.isClosed) _events.add(null);
  }

  @override
  Future<List<BookmarkedViolation>> listAll() async => _mem.values.toList();

  @override
  Future<BookmarkedViolation?> lookupByFingerprint(String fingerprint) async {
    for (final bm in _mem.values) {
      if (bm.fingerprint == fingerprint) return bm;
    }
    return null;
  }

  @override
  Future<void> addOrUpdate(BookmarkedViolation bookmark) async {
    _mem[bookmark.id] = bookmark;
    _write();
  }

  @override
  Future<void> remove(String bookmarkId) async {
    _mem.remove(bookmarkId);
    _write();
  }

  @override
  Stream<void> get changed => _events.stream;

  Future<void> dispose() => _events.close();
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
  Violation? violation,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...telemetryDeclinedOverrides(), ...overrides],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          L10N.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: BookmarkColumnIcon(violation: violation ?? _violation),
        ),
      ),
    ),
  );
  // Resolve the stream provider.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  group('BookmarkColumnIcon', () {
    testWidgets('renders outline icon when no bookmark exists', (tester) async {
      await _pump(
        tester,
        overrides: [
          violationBookmarkStoreProvider.overrideWithValue(
            _FakeBookmarkStore(),
          ),
        ],
      );
      expect(
        find.byKey(const ValueKey('bookmarkColumnIcon-off')),
        findsOneWidget,
      );
    });

    testWidgets('renders filled icon when a bookmark exists', (tester) async {
      await _pump(
        tester,
        overrides: [
          violationBookmarkStoreProvider.overrideWithValue(
            _FakeBookmarkStore(initial: [_bookmark()]),
          ),
        ],
      );
      expect(
        find.byKey(const ValueKey('bookmarkColumnIcon-on')),
        findsOneWidget,
      );
    });

    testWidgets(
      'renders stale variant when bookmark.lastSeenRunId lags '
      'behind the latest run id',
      (tester) async {
        await _pump(
          tester,
          overrides: [
            violationBookmarkStoreProvider.overrideWithValue(
              _FakeBookmarkStore(
                initial: [_bookmark(lastSeenRunId: 'old-run')],
              ),
            ),
            bookmarkFreshnessProvider.overrideWith(
              () => _FixedRunId('new-run'),
            ),
          ],
        );
        expect(
          find.byKey(const ValueKey('bookmarkColumnIcon-on-stale')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'tap on outline icon opens the bookmark dialog in create mode',
      (tester) async {
        await _pump(
          tester,
          overrides: [
            violationBookmarkStoreProvider.overrideWithValue(
              _FakeBookmarkStore(),
            ),
          ],
        );
        expect(find.byType(BookmarkDialog), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('bookmarkColumnIcon-off')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(BookmarkDialog), findsOneWidget);
        expect(
          tester.widget<BookmarkDialog>(find.byType(BookmarkDialog)).existing,
          isNull,
        );
        expect(find.text('Add bookmark'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'tap on filled icon removes the bookmark + shows undo snackbar',
      (tester) async {
        final store = _FakeBookmarkStore(initial: [_bookmark()]);
        await _pump(
          tester,
          overrides: [
            violationBookmarkStoreProvider.overrideWithValue(store),
          ],
        );
        await tester.tap(
          find.byKey(const ValueKey('bookmarkColumnIcon-on')),
        );
        // Let the remove + snackbar settle.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 10));
        expect(store.removed, isTrue);
        expect(find.text('Bookmark removed.'), findsOneWidget);
        expect(find.text('Undo'), findsOneWidget);
      },
    );

    testWidgets(
      'Undo after the store was rebuilt restores the bookmark without '
      'erasing ones made since',
      (tester) async {
        final first = _bookmark(color: '#FF5722');
        final second = BookmarkedViolation(
          id: 'bm-2',
          fingerprint: 'fp-other-violation',
          ruleId: 'verilator/WIDTH',
          filePath: '/b.sv',
          lineNumber: 40,
          snippet: 'width mismatch',
          createdAt: DateTime.utc(2026, 2),
          updatedAt: DateTime.utc(2026, 2),
        );
        // The project's bookmark file.
        final disk = <String, BookmarkedViolation>{first.id: first};
        await _pump(
          tester,
          overrides: [
            violationBookmarkStoreProvider.overrideWith((ref) {
              final store = _SnapshotStore(disk);
              ref.onDispose(store.dispose);
              return store;
            }),
          ],
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(BookmarkColumnIcon)),
        );

        // Remove the first bookmark. Its snackbar, with Undo, stays up.
        await tester.tap(find.byKey(const ValueKey('bookmarkColumnIcon-on')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 10));
        expect(disk, isEmpty);
        expect(find.text('Undo'), findsOneWidget);

        // The tab's store is rebuilt while the snackbar is up — in the app a
        // severity-override edit changes the project the store is keyed on.
        container.invalidate(violationBookmarkStoreProvider);
        await tester.pump();
        // A second bookmark is made through the new store.
        await container
            .read(violationBookmarkStoreProvider)
            .addOrUpdate(second);
        // Let the snackbar finish sliding in; it ignores taps until then.
        await tester.pump(const Duration(milliseconds: 500));
        expect(disk.keys, [second.id]);

        await tester.tap(find.text('Undo'));
        await tester.pump();

        expect(
          disk.keys,
          unorderedEquals([first.id, second.id]),
          reason:
              'Undo must write through the live store. The store from before '
              'the rebuild never saw the second bookmark, and its write '
              'replaces the whole file with what it holds',
        );
        expect(disk[first.id]!.fingerprint, first.fingerprint);
        expect(disk[first.id]!.color, first.color);
        expect(disk[first.id]!.createdAt, first.createdAt);
        expect(disk[second.id]!.fingerprint, second.fingerprint);
        final live = await container
            .read(violationBookmarkStoreProvider)
            .listAll();
        expect(
          live.map((b) => b.id),
          unorderedEquals([first.id, second.id]),
          reason: 'the table reads the live store, so it shows both',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('color swatch renders when bookmark.color is set', (
      tester,
    ) async {
      await _pump(
        tester,
        overrides: [
          violationBookmarkStoreProvider.overrideWithValue(
            _FakeBookmarkStore(
              initial: [_bookmark(color: '#FF5722')],
            ),
          ),
        ],
      );
      // Icon present plus the inline swatch sibling Container with a
      // colored decoration — assertion is shape-based to keep the
      // test robust to padding changes.
      expect(
        find.byKey(const ValueKey('bookmarkColumnIcon-on')),
        findsOneWidget,
      );
      final swatches = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) {
            final dec = c.decoration;
            return dec is BoxDecoration && dec.shape == BoxShape.circle;
          });
      expect(swatches, isNotEmpty);
    });

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
                  _FakeBookmarkStore(initial: [_bookmark()]),
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
