// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_telemetry/crux_telemetry.dart';
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
import 'package:lintcrux/features/bookmarks/widgets/bookmark_dialog.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/bookmarks/violation_bookmark_store_provider.dart';

import '../../../support/telemetry_test_store.dart';

const _violation = Violation(
  engineId: 'verilator',
  ruleId: 'verilator/UNUSEDSIGNAL',
  severity: Severity.warning,
  message: 'unused signal foo',
  location: SourceLocation(file: '/a.sv', line: 12, column: 1),
);

BookmarkedViolation _existing({String? note, String? color}) {
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
    note: note,
    color: color,
  );
}

class _RecordingStore implements ViolationBookmarkStore {
  final List<BookmarkedViolation> saved = [];
  final List<String> removed = [];
  final StreamController<void> _events = StreamController<void>.broadcast();

  @override
  Future<List<BookmarkedViolation>> listAll() async => List.from(saved);

  @override
  Future<BookmarkedViolation?> lookupByFingerprint(String fingerprint) async {
    for (final bm in saved) {
      if (bm.fingerprint == fingerprint) return bm;
    }
    return null;
  }

  @override
  Future<void> addOrUpdate(BookmarkedViolation bookmark) async {
    saved
      ..removeWhere((b) => b.id == bookmark.id)
      ..add(bookmark);
    _events.add(null);
  }

  @override
  Future<void> remove(String bookmarkId) async {
    removed.add(bookmarkId);
    saved.removeWhere((b) => b.id == bookmarkId);
    _events.add(null);
  }

  @override
  Stream<void> get changed => _events.stream;
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required List<Override> overrides,
  required Widget dialog,
  Locale locale = const Locale('en'),
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
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => dialog,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('BookmarkDialog', () {
    testWidgets('create mode renders blank fields + violation context', (
      tester,
    ) async {
      await _pumpDialog(
        tester,
        overrides: [
          violationBookmarkStoreProvider.overrideWithValue(_RecordingStore()),
        ],
        dialog: const BookmarkDialog(violation: _violation),
      );
      expect(find.text('Add bookmark'), findsOneWidget);
      expect(find.text(_violation.ruleId), findsOneWidget);
      expect(find.textContaining(_violation.location.file), findsOneWidget);
      // Note field empty, hint visible.
      expect(
        find.byKey(const ValueKey('bookmarkDialogNoteField')),
        findsOneWidget,
      );
    });

    testWidgets(
      'edit mode pre-fills note + opens with edit title',
      (tester) async {
        final store = _RecordingStore();
        await store.addOrUpdate(
          _existing(note: 'prior note', color: '#FF9800'),
        );
        await _pumpDialog(
          tester,
          overrides: [
            violationBookmarkStoreProvider.overrideWithValue(store),
          ],
          dialog: BookmarkDialog(existing: store.saved.first),
        );
        expect(find.text('Edit bookmark'), findsOneWidget);
        expect(find.text('prior note'), findsAtLeastNWidgets(1));
      },
    );

    testWidgets(
      'Save with non-empty note + color dispatches addOrUpdate',
      (tester) async {
        final store = _RecordingStore();
        await _pumpDialog(
          tester,
          overrides: [
            violationBookmarkStoreProvider.overrideWithValue(store),
          ],
          dialog: const BookmarkDialog(violation: _violation),
        );
        await tester.enterText(
          find.byKey(const ValueKey('bookmarkDialogNoteField')),
          'follow up later',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('bookmarkDialogSave')));
        await tester.pumpAndSettle();
        expect(store.saved, hasLength(1));
        expect(store.saved.first.note, 'follow up later');
      },
    );

    testWidgets(
      'Cancel with no edits closes immediately',
      (tester) async {
        final store = _RecordingStore();
        await _pumpDialog(
          tester,
          overrides: [
            violationBookmarkStoreProvider.overrideWithValue(store),
          ],
          dialog: const BookmarkDialog(violation: _violation),
        );
        await tester.tap(find.byKey(const ValueKey('bookmarkDialogCancel')));
        await tester.pumpAndSettle();
        expect(find.text('Add bookmark'), findsNothing);
        expect(store.saved, isEmpty);
      },
    );

    testWidgets(
      'Cancel with edits surfaces the discard-confirm dialog',
      (tester) async {
        final store = _RecordingStore();
        await _pumpDialog(
          tester,
          overrides: [
            violationBookmarkStoreProvider.overrideWithValue(store),
          ],
          dialog: const BookmarkDialog(violation: _violation),
        );
        await tester.enterText(
          find.byKey(const ValueKey('bookmarkDialogNoteField')),
          'about to abandon',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('bookmarkDialogCancel')));
        await tester.pumpAndSettle();
        expect(find.text('Discard changes?'), findsOneWidget);
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
            final store = _RecordingStore();
            await _pumpDialog(
              tester,
              locale: loc,
              overrides: [
                violationBookmarkStoreProvider.overrideWithValue(store),
              ],
              dialog: const BookmarkDialog(violation: _violation),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    });
  });

  group('bookmark.saved telemetry', () {
    // The panel-open counter says whether the bookmark panel was opened;
    // this one says whether anything was ever put in it.
    Future<_Recorder> save(
      WidgetTester tester, {
      required Widget dialog,
      String note = '',
    }) async {
      final recorder = _Recorder();
      await _pumpDialog(
        tester,
        overrides: [
          violationBookmarkStoreProvider.overrideWithValue(_RecordingStore()),
          telemetryServiceProvider.overrideWithValue(recorder),
        ],
        dialog: dialog,
      );
      if (note.isNotEmpty) {
        await tester.enterText(
          find.byKey(const ValueKey('bookmarkDialogNoteField')),
          note,
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('bookmarkDialogSave')));
      await tester.pumpAndSettle();
      return recorder;
    }

    testWidgets('a new bookmark reports edit: false, note: false', (
      tester,
    ) async {
      final recorder = await save(
        tester,
        dialog: const BookmarkDialog(violation: _violation),
      );

      final event = recorder.only('bookmark.saved');
      expect(event.properties, <String, Object?>{
        'edit': false,
        'note': false,
      });
    });

    testWidgets('a note reports note: true and never its text', (tester) async {
      final recorder = await save(
        tester,
        dialog: const BookmarkDialog(violation: _violation),
        note: 'revisit after the clock-domain rework',
      );

      final event = recorder.only('bookmark.saved');
      expect(event.properties['note'], isTrue);
      // The note is the user's own words about their own design, and the
      // violation it hangs off carries a rule id, a file and a message. None
      // of it may appear in an event.
      expect(event.properties.keys.toSet(), <String>{'edit', 'note'});
      expect(
        event.properties.values.whereType<String>(),
        isEmpty,
        reason: 'both properties are bools; no free-form value can ride along',
      );
    });

    testWidgets('re-saving an existing bookmark reports edit: true', (
      tester,
    ) async {
      // A bookmark that is only ever created is a flag; one that is revisited
      // is a triage queue.
      final recorder = await save(
        tester,
        dialog: BookmarkDialog(existing: _existing(note: 'first pass')),
      );

      expect(recorder.only('bookmark.saved').properties['edit'], isTrue);
    });

    testWidgets('cancelling records nothing', (tester) async {
      final recorder = _Recorder();
      await _pumpDialog(
        tester,
        overrides: [
          violationBookmarkStoreProvider.overrideWithValue(_RecordingStore()),
          telemetryServiceProvider.overrideWithValue(recorder),
        ],
        dialog: const BookmarkDialog(violation: _violation),
      );

      await tester.tap(find.byKey(const ValueKey('bookmarkDialogCancel')));
      await tester.pumpAndSettle();

      expect(
        recorder.events,
        isEmpty,
        reason: 'the counter is a success path, not an attempt',
      );
    });
  });
}

/// A [TelemetryService] that keeps every event it is handed.
class _Recorder implements TelemetryService {
  final List<TelemetryEvent> events = <TelemetryEvent>[];

  TelemetryEvent only(String name) =>
      events.where((e) => e.name == name).single;

  @override
  void record(TelemetryEvent event) => events.add(event);
}
