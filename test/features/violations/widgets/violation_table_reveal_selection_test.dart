// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// A selection made outside the table brings its row into view.
//
// Find in Violations, bookmarks and the cross-probe all select through
// `selectedViolationProvider`. The list is virtualized, so a row far from the
// viewport is not built, and selecting it used to leave the table where it
// was: the Details pane changed, the row was highlighted out of sight, and
// the choice looked as if it had done nothing.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/violations/widgets/violation_table.dart';
import 'package:lintcrux/features/violations/widgets/violation_table_row.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';

const _rowCount = 400;

Violation _v(int line) => Violation(
  engineId: 'verilator',
  ruleId: 'verilator/R$line',
  severity: Severity.warning,
  message: 'm$line',
  location: SourceLocation(file: '/x/y.sv', line: line, column: 1),
);

Future<ProviderContainer> _pump(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1200, 700)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = InMemoryViolationStore()
    ..replaceFromEngine('verilator', [
      for (var i = 1; i <= _rowCount; i++) _v(i),
    ]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        violationStoreProvider.overrideWithValue(store),
        engineRegistryProvider.overrideWithValue(EngineRegistry(const [])),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          L10N.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(body: ViolationTable()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ViolationTable)),
  );
  // Sorting by line puts row N at index N-1.
  container
      .read(violationTableStateProvider.notifier)
      .setSort(ViolationTableColumn.line, ascending: true);
  await tester.pumpAndSettle();
  return container;
}

ScrollableState _list(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).last);

Finder _row(Violation v) => find.byKey(ValueKey(v));

/// Whether [v]'s row is built and overlaps the table's visible area.
bool _inView(WidgetTester tester, Violation v) {
  if (_row(v).evaluate().isEmpty) return false;
  final rect = tester.getRect(_row(v));
  final list = tester.getRect(find.byType(Scrollable).last);
  return rect.bottom > list.top && rect.top < list.bottom;
}

void main() {
  testWidgets('a row selected from outside scrolls into view from the bottom', (
    tester,
  ) async {
    final container = await _pump(tester);
    final scroll = _list(tester);
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final target = _v(3);
    expect(_row(target), findsNothing, reason: 'row 3 starts far above');

    container.read(selectedViolationProvider.notifier).select(target);
    await tester.pumpAndSettle();

    expect(_row(target), findsOneWidget, reason: 'the row has been built');
    expect(_inView(tester, target), isTrue, reason: 'and it is on screen');
  });

  testWidgets('a row selected from outside scrolls down to it as well', (
    tester,
  ) async {
    final container = await _pump(tester);
    final target = _v(300);
    expect(_row(target), findsNothing);

    container.read(selectedViolationProvider.notifier).select(target);
    await tester.pumpAndSettle();

    expect(_inView(tester, target), isTrue);
  });

  testWidgets('a row that is already on screen does not move the list', (
    tester,
  ) async {
    final container = await _pump(tester);
    final before = _list(tester).position.pixels;

    container.read(selectedViolationProvider.notifier).select(_v(2));
    await tester.pumpAndSettle();

    expect(_list(tester).position.pixels, before);
  });

  testWidgets('clicking a row in the table does not move the list', (
    tester,
  ) async {
    await _pump(tester);
    final scroll = _list(tester);
    // Park the list so the row below is cut off by the bottom edge.
    scroll.position.jumpTo(14);
    await tester.pumpAndSettle();
    final before = scroll.position.pixels;
    final listRect = tester.getRect(find.byType(Scrollable).last);
    final partial = find
        .byType(ViolationTableRow)
        .evaluate()
        .map((e) {
          return e.widget as ViolationTableRow;
        })
        .firstWhere((r) {
          final rect = tester.getRect(_row(r.violation));
          return rect.bottom > listRect.bottom - 8 &&
              rect.top < listRect.bottom;
        });

    await tester.tapAt(
      Offset(
        tester.getRect(_row(partial.violation)).center.dx,
        listRect.bottom - 3,
      ),
    );
    await tester.pumpAndSettle();

    expect(scroll.position.pixels, before);
  });
}
