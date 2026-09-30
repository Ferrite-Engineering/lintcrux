// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/source_preview/widgets/source_preview_pane.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/source_preview/source_preview_provider.dart';
import 'package:lintcrux/services/source_preview/source_preview_service.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';

/// [SourceReader] test double serving canned in-memory file content, or
/// simulating a missing file / a thrown read failure.
class _FakeSourceReader implements SourceReader {
  _FakeSourceReader(this._files, {this.throwFor, this.gate});

  final Map<String, List<String>> _files;
  final String? throwFor;
  final Completer<void>? gate;

  @override
  Future<List<String>?> readLines(String file) async {
    if (gate != null) await gate!.future;
    if (throwFor != null && file == throwFor) {
      throw const FileSystemExceptionStub();
    }
    return _files[file];
  }
}

/// Minimal stand-in exception — the service only cares that reading
/// failed, not the specific exception type of the fake.
class FileSystemExceptionStub implements Exception {
  const FileSystemExceptionStub();
  @override
  String toString() => 'FileSystemExceptionStub';
}

void main() {
  const violation = Violation(
    engineId: 'verilator',
    ruleId: 'verilator/UNUSEDSIGNAL',
    severity: Severity.warning,
    message: 'unused signal foo',
    location: SourceLocation(file: '/p/a.sv', line: 5, column: 3),
  );

  Widget wrap(
    Widget child, {
    Locale locale = const Locale('en'),
    List<Override> overrides = const [],
    List<Violation> storeViolations = const [violation],
  }) {
    final store = InMemoryViolationStore()
      ..replaceFromEngine('verilator', storeViolations);
    addTearDown(store.dispose);
    return ProviderScope(
      overrides: [
        violationStoreProvider.overrideWithValue(store),
        ...overrides,
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          L10N.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
  }

  L10N l10nOf(WidgetTester tester) =>
      L10N.of(tester.element(find.byType(SourcePreviewPane)));

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(SourcePreviewPane)));

  Future<void> selectViolation(WidgetTester tester, [Violation v = violation]) {
    containerOf(tester).read(selectedViolationProvider.notifier).select(v);
    return tester.pump();
  }

  Override readerOverride(
    Map<String, List<String>> files, {
    String? throwFor,
    Completer<void>? gate,
    int contextLines = 3,
  }) => sourcePreviewServiceProvider.overrideWithValue(
    SourcePreviewService(
      reader: _FakeSourceReader(files, throwFor: throwFor, gate: gate),
      contextLines: contextLines,
    ),
  );

  group('SourcePreviewPane', () {
    testWidgets('renders the empty state when no violation is selected', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const SourcePreviewPane()));
      await tester.pumpAndSettle();
      expect(find.text(l10nOf(tester).sourcePreviewEmpty), findsOneWidget);
    });

    testWidgets(
      'shows the loading spinner while the source window is being read',
      (tester) async {
        final gate = Completer<void>();
        await tester.pumpWidget(
          wrap(
            const SourcePreviewPane(),
            overrides: [readerOverride({}, gate: gate)],
          ),
        );
        await tester.pumpAndSettle();
        await selectViolation(tester);
        // One pump (not settle) so the read is still pending on the gate.
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        gate.complete();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'renders the file-missing empty state (with the file path) when '
      'the file cannot be read',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            const SourcePreviewPane(),
            overrides: [readerOverride({})], // no entry for '/p/a.sv'
          ),
        );
        await tester.pumpAndSettle();
        await selectViolation(tester);
        await tester.pumpAndSettle();

        expect(
          find.text(l10nOf(tester).sourcePreviewFileMissing('/p/a.sv')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'renders the error branch text when the underlying read throws',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            const SourcePreviewPane(),
            overrides: [
              // windowAround only catches FileSystemException; a
              // generic thrown error propagates to the FutureProvider
              // as an AsyncError, exercising the `error:` branch.
              sourcePreviewServiceProvider.overrideWithValue(
                _ThrowingSourcePreviewService(),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await selectViolation(tester);
        await tester.pumpAndSettle();

        expect(
          find.textContaining('boom'),
          findsOneWidget,
          reason: 'the error text should surface the exception message',
        );
      },
    );

    testWidgets(
      'renders the source listing with gutter line numbers and the '
      'primary highlight on the violation line',
      (tester) async {
        final lines = List<String>.generate(20, (i) => 'line ${i + 1}');
        await tester.pumpWidget(
          wrap(
            const SourcePreviewPane(),
            overrides: [
              readerOverride({'/p/a.sv': lines}),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await selectViolation(tester);
        await tester.pumpAndSettle();

        // Header shows the file path.
        expect(find.text('/p/a.sv'), findsOneWidget);
        // Window is violation.location.line=5 +/- 3 => lines 2..8.
        expect(find.text('line 2'), findsOneWidget);
        expect(find.text('line 5'), findsOneWidget);
        expect(find.text('line 8'), findsOneWidget);
        expect(find.text('line 1'), findsNothing);
        expect(find.text('line 9'), findsNothing);
        // Gutter line-number labels are rendered as their own Text widgets.
        expect(find.text('5'), findsOneWidget);
      },
    );

    testWidgets(
      'highlights related-location lines that fall inside the window',
      (tester) async {
        final lines = List<String>.generate(20, (i) => 'line ${i + 1}');
        final withRelated = violation.copyWith(
          relatedLocations: const [
            SourceLocation(file: '/p/a.sv', line: 6, column: 1),
            // Outside the window (line 5 +/- 3 => 2..8) — must not throw
            // and must not be counted as a related highlight.
            SourceLocation(file: '/p/a.sv', line: 19, column: 1),
            // Different file — never highlighted here.
            SourceLocation(file: '/p/other.sv', line: 6, column: 1),
          ],
        );
        await tester.pumpWidget(
          wrap(
            const SourcePreviewPane(),
            overrides: [
              readerOverride({'/p/a.sv': lines}),
            ],
            storeViolations: [withRelated],
          ),
        );
        await tester.pumpAndSettle();
        await selectViolation(tester, withRelated);
        await tester.pumpAndSettle();

        expect(find.text('line 6'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('SourcePreviewPane locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders empty and populated states in $locale', (
        tester,
      ) async {
        final lines = List<String>.generate(10, (i) => 'line ${i + 1}');
        await tester.pumpWidget(
          wrap(
            const SourcePreviewPane(),
            locale: locale,
            overrides: [
              readerOverride({'/p/a.sv': lines}),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(l10nOf(tester).sourcePreviewEmpty), findsOneWidget);

        await selectViolation(tester);
        await tester.pumpAndSettle();
        expect(find.text('/p/a.sv'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'failed for $locale');
      });
    }
  });
}

/// [SourcePreviewService] double whose [windowAround] always throws a
/// plain (non-[FileSystemException]) error, exercising the
/// [SourcePreviewPane] `error:` branch of `AsyncValue.when` — the
/// production reader only ever swallows [FileSystemException] into a
/// `null`/empty window, so a generic throw is the only way to reach
/// that branch from a widget test.
class _ThrowingSourcePreviewService implements SourcePreviewService {
  @override
  Future<SourceWindow> windowAround({
    required String file,
    required int line,
    Set<int> relatedLineSet = const <int>{},
  }) {
    throw StateError('boom');
  }

  @override
  SourceReader get reader => throw UnimplementedError();

  @override
  int get contextLines => throw UnimplementedError();
}
