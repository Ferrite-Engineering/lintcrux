// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/violations/widgets/violation_table.dart';
import 'package:lintcrux/features/violations/widgets/violation_table_header.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/plugins/dashboard_banners_provider.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';
import '../../../support/telemetry_test_store.dart';

class _FakeEngine implements LintEngine {
  _FakeEngine(this.id);
  @override
  final String id;
  @override
  String get displayName => id;
  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.systemVerilog},
  );
  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async => null;
  @override
  Stream<Violation> run(LintRunRequest request) async* {}
  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) => run(request);
  @override
  void cancel() {}
}

Violation _v(
  String engineId,
  String rule, {
  Severity severity = Severity.warning,
  String file = '/x/y.sv',
  int line = 1,
  String message = 'msg',
}) => Violation(
  engineId: engineId,
  ruleId: '$engineId/$rule',
  severity: severity,
  message: message,
  location: SourceLocation(file: file, line: line, column: 1),
);

Widget _harness({
  required InMemoryViolationStore store,
  EngineRegistry? registry,
  Locale locale = const Locale('en'),
  List<DashboardBannerBuilder>? banners,
}) {
  return ProviderScope(
    overrides: [
      ...telemetryDeclinedOverrides(),
      violationStoreProvider.overrideWithValue(store),
      engineRegistryProvider.overrideWithValue(
        registry ?? EngineRegistry([_FakeEngine('verilator')]),
      ),
      if (banners != null) dashboardBannersProvider.overrideWithValue(banners),
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
  );
}

void main() {
  group('ViolationTable widget', () {
    testWidgets('shows the empty state when the store is empty', (
      tester,
    ) async {
      final store = InMemoryViolationStore();
      await tester.pumpWidget(_harness(store: store));
      await tester.pumpAndSettle();
      expect(find.text('No violations.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders one row per violation', (tester) async {
      final store = InMemoryViolationStore()
        ..replaceFromEngine('verilator', [
          _v('verilator', 'A', message: 'first'),
          _v('verilator', 'B', message: 'second'),
          _v('verilator', 'C', message: 'third'),
        ]);
      await tester.pumpWidget(_harness(store: store));
      await tester.pumpAndSettle();
      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsOneWidget);
      expect(find.text('third'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('clicking a column header sorts by that column', (
      tester,
    ) async {
      final store = InMemoryViolationStore()
        ..replaceFromEngine('verilator', [
          _v('verilator', 'B', message: 'beta'),
          _v('verilator', 'A', message: 'alpha'),
        ]);
      await tester.pumpWidget(_harness(store: store));
      await tester.pumpAndSettle();
      // Default sort is by severity (both same), so insertion order
      // preserved: 'beta' first, then 'alpha'.
      // Click the rule column header.
      await tester.tap(find.byKey(const ValueKey('violationTableHeader-rule')));
      await tester.pumpAndSettle();
      final state = ProviderScope.containerOf(
        tester.element(find.byType(ViolationTable)),
      ).read(violationTableStateProvider);
      expect(state.sortColumn, ViolationTableColumn.rule);
      expect(state.sortAscending, isTrue);
    });

    testWidgets('toggling a severity filter chip narrows the visible set', (
      tester,
    ) async {
      final store = InMemoryViolationStore()
        ..replaceFromEngine('verilator', [
          _v('verilator', 'E', severity: Severity.error, message: 'err'),
          _v('verilator', 'W', message: 'warn'),
        ]);
      await tester.pumpWidget(_harness(store: store));
      await tester.pumpAndSettle();
      expect(find.text('err'), findsOneWidget);
      expect(find.text('warn'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('violationFilterChip-severity-error')),
      );
      await tester.pumpAndSettle();
      expect(find.text('err'), findsOneWidget);
      expect(find.text('warn'), findsNothing);
    });

    testWidgets('row checkbox toggles selection state', (tester) async {
      final store = InMemoryViolationStore();
      final v = _v('verilator', 'A');
      store.replaceFromEngine('verilator', [v]);
      await tester.pumpWidget(_harness(store: store));
      await tester.pumpAndSettle();
      final id = ViolationTableState.idOf(v);
      await tester.tap(find.byKey(ValueKey('violationRowCheckbox-$id')));
      await tester.pumpAndSettle();
      final state = ProviderScope.containerOf(
        tester.element(find.byType(ViolationTable)),
      ).read(violationTableStateProvider);
      expect(state.selectedRuleIds, contains(id));
    });

    testWidgets('carries no footer summary of its own', (tester) async {
      // The table used to end in a strip rendering `violationStatusSummary`
      // over `visibleViolationsProvider` — the exact string LintcruxStatusBar
      // renders at the window bottom, from the same provider. The
      // window-bottom bar is the suite-wide surface and is now the only one;
      // `lintcrux_status_bar_test.dart` covers the tally itself.
      final store = InMemoryViolationStore()
        ..replaceFromEngine('verilator', [
          _v('verilator', 'A', severity: Severity.error),
          _v('verilator', 'B'),
          _v('verilator', 'C', severity: Severity.note),
        ]);
      await tester.pumpWidget(_harness(store: store));
      await tester.pumpAndSettle();
      expect(find.textContaining('3 total'), findsNothing);
    });

    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('locale ${locale.toLanguageTag()}: renders empty state', (
        tester,
      ) async {
        final store = InMemoryViolationStore();
        await tester.pumpWidget(_harness(store: store, locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  // The read-only viewer's engine filter chips must NOT read the
  // engine registry (which eagerly builds run-time runners that call
  // `dart:io Platform` and crash the web viewer). They are derived from the
  // engine ids present in the loaded report instead. These tests render the
  // table WITHOUT any `engineRegistryProvider` override — a proxy for the
  // web viewer, where the registry must never be touched.
  group('dashboard banners', () {
    // The seam was declared, overridden by the Pro overlay with three
    // banners, and read by nothing, so none of them ever rendered.
    testWidgets('each contribution renders above the filters, in order', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          store: InMemoryViolationStore(),
          banners: [
            (context, ref) => const Text('first banner'),
            (context, ref) => const Text('second banner'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final first = tester.getTopLeft(find.text('first banner'));
      final second = tester.getTopLeft(find.text('second banner'));
      final header = tester.getTopLeft(find.byType(ViolationTableHeader));
      expect(first.dy, lessThan(second.dy));
      expect(second.dy, lessThan(header.dy));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a contribution reads providers through the table ref', (
      tester,
    ) async {
      final store = InMemoryViolationStore()
        ..replaceFromEngine('verilator', [_v('verilator', 'A')]);
      await tester.pumpWidget(
        _harness(
          store: store,
          banners: [
            (context, ref) =>
                Text('count ${ref.watch(violationStoreProvider).count}'),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('count 1'), findsOneWidget);
    });
  });

  group('ViolationFilterChips engine chips are report-derived', () {
    Widget registryFreeHarness(InMemoryViolationStore store) {
      return ProviderScope(
        overrides: [
          ...telemetryDeclinedOverrides(),
          violationStoreProvider.overrideWithValue(store),
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
      );
    }

    testWidgets('renders a chip per engine present in the report, and none '
        'for absent engines', (tester) async {
      final store = InMemoryViolationStore()
        ..replaceFromEngine('verilator', [_v('verilator', 'A')])
        ..replaceFromEngine('verible', [_v('verible', 'B')]);
      await tester.pumpWidget(registryFreeHarness(store));
      await tester.pumpAndSettle();
      // No red screen despite no engineRegistryProvider override.
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('violationFilterChip-engine-verilator')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('violationFilterChip-engine-verible')),
        findsOneWidget,
      );
      // An engine LintCrux *can* run but that is absent from this report
      // gets no chip.
      expect(
        find.byKey(const ValueKey('violationFilterChip-engine-slang')),
        findsNothing,
      );
    });

    testWidgets('an empty store shows no engine chips', (tester) async {
      final store = InMemoryViolationStore();
      await tester.pumpWidget(registryFreeHarness(store));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('violationFilterChip-engine-verilator')),
        findsNothing,
      );
    });
  });

  // Each applied filter change re-derives the whole table (filter + sort +
  // copy over the store), so the text fields apply once typing settles, not
  // per keystroke.
  group('ViolationFilterChips text filters are debounced', () {
    testWidgets('the rule filter applies once, after typing settles', (
      tester,
    ) async {
      final store = InMemoryViolationStore()
        ..replaceFromEngine('verilator', [
          _v('verilator', 'A', message: 'alpha'),
          _v('verilator', 'B', message: 'beta'),
        ]);
      await tester.pumpWidget(_harness(store: store));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ViolationTable)),
      );
      final field = find.byKey(const ValueKey('violationFilterRuleField'));
      for (final typed in const ['a', 'al', 'alp', 'alph']) {
        await tester.enterText(field, typed);
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          container.read(violationTableStateProvider).ruleSubstring,
          isEmpty,
          reason: 'applied mid-typing at "$typed"',
        );
      }
      await tester.pump(const Duration(milliseconds: 200));
      expect(container.read(violationTableStateProvider).ruleSubstring, 'alph');
      expect(container.read(visibleViolationsProvider), hasLength(1));
    });

    testWidgets('the file filter applies once, after typing settles', (
      tester,
    ) async {
      final store = InMemoryViolationStore()
        ..replaceFromEngine('verilator', [_v('verilator', 'A')]);
      await tester.pumpWidget(_harness(store: store));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ViolationTable)),
      );
      final field = find.byKey(const ValueKey('violationFilterFileField'));
      for (final typed in const ['*', '*.', '*.s', '*.sv']) {
        await tester.enterText(field, typed);
        await tester.pump(const Duration(milliseconds: 50));
        expect(container.read(violationTableStateProvider).fileGlob, isEmpty);
      }
      await tester.pump(const Duration(milliseconds: 200));
      expect(container.read(violationTableStateProvider).fileGlob, '*.sv');
    });
  });

  // Live-testing at the default 800x500 window put the center pane at
  // ~450px wide; the wrapped filter chrome grew taller than the pane
  // and the table Column overflowed bottom by 198px. The header region
  // now caps its height (scrolling within its own bounded box) so the
  // virtualized list always keeps at least three rows of space.
  group('squeezed pane ("crop, don\'t crush")', () {
    ScrollPosition headerScrollPosition(WidgetTester tester) {
      final scrollable = find
          .ancestor(
            of: find.byType(ViolationTableHeader),
            matching: find.byType(Scrollable),
          )
          .first;
      return tester.state<ScrollableState>(scrollable).position;
    }

    for (final size in const [Size(450, 300), Size(450, 160)]) {
      testWidgets(
        '${size.width.toInt()}x${size.height.toInt()}: no RenderFlex '
        'overflow and the list keeps its rows',
        (tester) async {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final store = InMemoryViolationStore()
            ..replaceFromEngine('verilator', [
              _v('verilator', 'A', message: 'first'),
              _v('verilator', 'B', message: 'second'),
              _v('verilator', 'C', message: 'third'),
            ]);
          await tester.pumpWidget(_harness(store: store));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          // The virtualized list survives the squeeze: the first row
          // is still laid out inside the reserved list region.
          expect(find.text('first'), findsOneWidget);
          // The header chrome no longer fits, so its bounded box has
          // scrollable overflow instead of a RenderFlex error.
          expect(
            headerScrollPosition(tester).maxScrollExtent,
            greaterThan(0),
          );
        },
      );
    }

    testWidgets('at a roomy pane the header region does not scroll — '
        'rendering is unchanged from the pre-fix layout', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = InMemoryViolationStore()
        ..replaceFromEngine('verilator', [_v('verilator', 'A')]);
      await tester.pumpWidget(_harness(store: store));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The SingleChildScrollView shrink-wraps to the header's natural
      // height: zero scroll extent means the guard is inert at normal
      // sizes.
      expect(headerScrollPosition(tester).maxScrollExtent, 0);
    });
  });
}
