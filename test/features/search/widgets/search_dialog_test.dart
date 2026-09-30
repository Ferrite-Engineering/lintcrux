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
import 'package:lintcrux/features/search/widgets/search_dialog.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';
import '../../../support/telemetry_test_store.dart';

/// Widget coverage for [SearchDialog] — the Find-in-Violations modal
/// wired to `focusSearch` (Cmd/Ctrl+F) / the toolbar Search button.
/// Covers the empty state, substring filtering (past the input
/// debounce), result-tap → `selectedViolationProvider` + dialog close,
/// and the standard four-locale sweep.
Violation _make(String rule, String file, int line) => Violation(
  engineId: 'verilator',
  ruleId: 'verilator/$rule',
  severity: Severity.warning,
  message: 'msg for $rule',
  location: SourceLocation(file: file, line: line, column: 1),
);

void main() {
  late InMemoryViolationStore store;

  setUp(() {
    store = InMemoryViolationStore()
      ..replaceFromEngine('verilator', <Violation>[
        _make('UNUSEDSIGNAL', '/a.sv', 3),
        _make('WIDTHTRUNC', '/b.sv', 9),
      ]);
  });
  tearDown(() => store.dispose());

  Widget wrap(Widget child, {Locale locale = const Locale('en')}) {
    return ProviderScope(
      overrides: <Override>[
        ...telemetryDeclinedOverrides(),
        violationStoreProvider.overrideWith((ref) => store),
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

  Finder input() => find.byKey(const ValueKey('searchDialogInput'));

  testWidgets('empty query renders a blank result area', (tester) async {
    await tester.pumpWidget(wrap(const SearchDialog()));
    final l10n = L10N.of(tester.element(find.byType(SearchDialog)));
    expect(find.text(l10n.searchDialogTitle), findsOneWidget);
    // Suite canon (CruxSearchDialog): an empty query shows neither rows
    // nor the no-results copy — that copy is reserved for a real query
    // with zero matches.
    expect(find.text(l10n.searchNoResults), findsNothing);
    expect(find.text('verilator/UNUSEDSIGNAL'), findsNothing);
  });

  testWidgets('typing a substring surfaces the matching violation', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const SearchDialog()));
    await tester.enterText(input(), 'UNUSED');
    // Past the 200 ms input debounce.
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('verilator/UNUSEDSIGNAL'), findsOneWidget);
    // The non-matching violation is filtered out.
    expect(find.text('verilator/WIDTHTRUNC'), findsNothing);
  });

  testWidgets('tapping a result selects the violation and closes', (
    tester,
  ) async {
    // Drive through showDialog so there is a real dialog route to pop.
    late BuildContext rootCtx;
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) {
            rootCtx = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    // Materialize the visible-violations derivation so the selection
    // auto-clear logic sees the row as present.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    )..read(visibleViolationsProvider);

    unawaited(
      showDialog<void>(
        context: rootCtx,
        builder: (_) => const SearchDialog(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SearchDialog), findsOneWidget);

    await tester.enterText(input(), 'UNUSED');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('verilator/UNUSEDSIGNAL'));
    await tester.pumpAndSettle();

    expect(find.byType(SearchDialog), findsNothing);
    expect(
      container.read(selectedViolationProvider)?.ruleId,
      'verilator/UNUSEDSIGNAL',
    );
  });

  testWidgets(
    'the root-scope launcher searches the root store and leaves the '
    'workspace alone',
    (tester) async {
      // The browser viewer's path: no WorkspaceRoot, and the report lives in
      // the root container, so the dialog must not be re-scoped to a tab.
      late BuildContext rootCtx;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) {
              rootCtx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      )..read(visibleViolationsProvider);

      unawaited(showViolationSearchDialog(rootCtx, activeTab: false));
      await tester.pumpAndSettle();
      expect(find.byType(SearchDialog), findsOneWidget);

      await tester.enterText(input(), 'WIDTH');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('verilator/WIDTHTRUNC'));
      await tester.pumpAndSettle();

      expect(find.byType(SearchDialog), findsNothing);
      expect(
        container.read(selectedViolationProvider)?.ruleId,
        'verilator/WIDTHTRUNC',
      );
      expect(container.exists(workspaceProvider), isFalse);
    },
  );

  for (final locale in const <Locale>[
    Locale('en'),
    Locale('zh', 'CN'),
    Locale('ja'),
    Locale('ko'),
  ]) {
    testWidgets('renders without error in ${locale.toLanguageTag()}', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const SearchDialog(), locale: locale));
      expect(find.byType(SearchDialog), findsOneWidget);
      final l10n = L10N.of(tester.element(find.byType(SearchDialog)));
      expect(find.text(l10n.searchDialogTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
