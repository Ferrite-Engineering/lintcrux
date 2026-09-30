// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The violation table from the keyboard: one Tab stop for the rows, the arrow
// keys, Home and End between them, and every pointer action on a row reachable
// without the pointer.

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:lintcrux/plugins/violation_context_menu_provider.dart';
import 'package:lintcrux/services/editor/click_to_source_service.dart';
import 'package:lintcrux/services/editor/editor_command_provider.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';

const _rowCount = 200;

Violation _v(int line) => Violation(
  engineId: 'verilator',
  ruleId: 'verilator/R$line',
  severity: Severity.warning,
  message: 'm$line',
  location: SourceLocation(file: '/x/y.sv', line: line, column: 1),
);

/// Records what the editor was asked to open; never spawns a process.
class _RecordingEditor implements ClickToSourceService {
  final List<SourceLocation> opened = <SourceLocation>[];

  @override
  Future<ClickToSourceResult> openInEditor(SourceLocation location) async {
    opened.add(location);
    return const ClickToSourceResult(
      success: true,
      command: RenderedEditorCommand(executable: 'code', arguments: []),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  _RecordingEditor? editor,
  List<ViolationContextMenuEntry> menu = const [],
  Locale? locale,
}) async {
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
        clickToSourceServiceProvider.overrideWithValue(
          editor ?? _RecordingEditor(),
        ),
        violationContextMenuEntriesProvider.overrideWithValue(menu),
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
        home: const Scaffold(body: ViolationTable()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ViolationTable)),
  );
  // Every row has the same severity, the default sort key, and the sort is
  // not stable; sorting by line puts row N at index N-1.
  container
      .read(violationTableStateProvider.notifier)
      .setSort(ViolationTableColumn.line, ascending: true);
  await tester.pumpAndSettle();
  return container;
}

bool _onRow(FocusStop stop) => stop.name.startsWith('Warning violation');

/// The line number named in a row's spoken sentence.
int? _lineOf(FocusStop stop) {
  final match = RegExp(r' line (\d+):').firstMatch(stop.name);
  return match == null ? null : int.parse(match.group(1)!);
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump();
}

bool _rowFocused() =>
    FocusManager.instance.primaryFocus?.debugLabel == 'Violation row';

/// Tabs into the rows, then Home, so the focused row is the first.
Future<void> _tabToRows(WidgetTester tester) async {
  for (var i = 0; i < 60 && !_rowFocused(); i++) {
    await _press(tester, LogicalKeyboardKey.tab);
  }
  expect(_rowFocused(), isTrue, reason: 'Tab reaches the rows');
  await _press(tester, LogicalKeyboardKey.home);
}

void main() {
  testWidgets('the rows are one Tab stop, however many there are', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk, context: 'violation table');
    expect(walk.stops.where(_onRow), hasLength(1));
    // The stop is on a row that is built, or Tab would skip the list.
    final line = _lineOf(walk.stops.firstWhere(_onRow));
    expect(find.text('m$line'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('Up, Down, Home and End move focus and the selection with it', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final container = await _pump(tester);
    await _tabToRows(tester);
    expect(container.read(selectedViolationProvider), _v(1));

    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_lineOf(describeFocus(tester)), 3);
    expect(container.read(selectedViolationProvider), _v(3));

    // End reaches a row that was never built, scrolls it into view and
    // focuses it once it has been laid out.
    await _press(tester, LogicalKeyboardKey.end);
    expect(_lineOf(describeFocus(tester)), _rowCount);
    expect(container.read(selectedViolationProvider), _v(_rowCount));
    final lastRow = tester.getRect(find.text('m$_rowCount'));
    final table = tester.getRect(find.byType(ViolationTable));
    expect(table.contains(lastRow.center), isTrue);

    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_lineOf(describeFocus(tester)), _rowCount, reason: 'stays at end');

    await _press(tester, LogicalKeyboardKey.home);
    expect(_lineOf(describeFocus(tester)), 1);
    expect(container.read(selectedViolationProvider), _v(1));
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_lineOf(describeFocus(tester)), 1, reason: 'stays at start');

    // The Tab stop followed: leaving the list and coming back returns to
    // the row last visited, not the first.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    final walk = await walkFocus(tester);
    expect(walk.stops.where(_onRow).map(_lineOf), [2]);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('Space toggles the check box and Enter opens the source', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final editor = _RecordingEditor();
    final container = await _pump(tester, editor: editor);
    await _tabToRows(tester);
    await _press(tester, LogicalKeyboardKey.arrowDown);

    await _press(tester, LogicalKeyboardKey.space);
    expect(
      container.read(violationTableStateProvider).selectedRuleIds,
      {ViolationTableState.idOf(_v(2))},
    );
    expect(describeFocus(tester).states, contains('checked'));

    await _press(tester, LogicalKeyboardKey.enter);
    expect(editor.opened, [_v(2).location]);
    expect(container.read(selectedViolationProvider), _v(2));
    handle.dispose();
  });

  testWidgets('Shift+F10 opens the row context menu for the focused row', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final activated = <Violation>[];
    await _pump(
      tester,
      menu: [
        ViolationContextMenuEntry(
          id: 'probe',
          labelBuilder: (_) => 'Probe entry',
          onActivate: (_, _, violation) => activated.add(violation),
        ),
      ],
    );
    await _tabToRows(tester);
    await _press(tester, LogicalKeyboardKey.arrowDown);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Probe entry'), findsOneWidget);

    await tester.tap(find.text('Probe entry'));
    await tester.pumpAndSettle();
    expect(activated, [_v(2)]);
    handle.dispose();
  });

  testWidgets('a clicked row is where Tab re-enters the list', (tester) async {
    final handle = tester.ensureSemantics();
    final container = await _pump(tester);

    await tester.tap(find.text('m5'));
    await tester.pumpAndSettle();
    expect(container.read(selectedViolationProvider), _v(5));

    final walk = await walkFocus(tester);
    expect(walk.stops.where(_onRow).map(_lineOf), [5]);
    handle.dispose();
  });

  // The row sentence and the list's keyboard hint are localized; the keys and
  // the selection that follows them are not locale-dependent, and must not
  // break in a CJK rendering.
  for (final locale in L10N.supportedLocales) {
    testWidgets('keyboard row movement in ${locale.toLanguageTag()}', (
      tester,
    ) async {
      final container = await _pump(tester, locale: locale);
      await _tabToRows(tester);
      expect(container.read(selectedViolationProvider), _v(1));
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(container.read(selectedViolationProvider), _v(2));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the focused row draws a focus ring and the others do not', (
    tester,
  ) async {
    await _pump(tester);
    BoxDecoration ringOf(int line) =>
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: find.ancestor(
                      of: find.text('m$line'),
                      matching: find.byType(ViolationTableRow),
                    ),
                    matching: find.byKey(
                      const ValueKey('violationRowFocusRing'),
                    ),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect(ringOf(1).border, isNull);

    await _tabToRows(tester);
    expect(ringOf(1).border, isNotNull);
    expect(ringOf(2).border, isNull);

    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(ringOf(1).border, isNull);
    expect(ringOf(2).border, isNotNull);
  });
}
