// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/rule.dart';
import 'package:lintcrux/features/rules/widgets/rules_panel.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/rules/rule_database_provider.dart';

/// The rule browser.
///
/// Without the rule browser the only way to reach the database it reads is
/// to select a violation and let the Inspector look up that one
/// rule. These tests are about the half that was missing — finding a rule you
/// have *not* already tripped over.
Future<ProviderContainer> _pump(WidgetTester tester) async {
  // A real surface size. The default 800x600 test window is narrower than the
  // engine-chip strip, and the strip is a lazy horizontal ListView — so the
  // last chips (svlint, cdc) are never built and a finder for them fails for
  // reasons that have nothing to do with the behaviour under test.
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer();
  addTearDown(container.dispose);

  // Resolve the database BEFORE pumping. The panel shows a
  // CircularProgressIndicator while it loads, and an indeterminate progress
  // indicator animates forever — so `pumpAndSettle` on a still-loading panel
  // times out rather than failing on anything real. Reading the future inside
  // `runAsync` lets the rootBundle load actually complete, after which the
  // panel builds straight into its data state.
  await tester.runAsync(() => container.read(ruleDatabaseProvider.future));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(body: RulesPanel()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('lists the whole catalog across every engine', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _pump(tester);
    // 645 rules across seven engines. The assertion is deliberately a floor
    // rather than an equality: rule metadata is community-extensible, so a
    // PR adding entries must not break the panel's test.
    expect(find.textContaining('rules'), findsWidgets);
    expect(find.byType(ListTile), findsWidgets);
  });

  testWidgets('an engine chip narrows the list to that engine', (
    tester,
  ) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _pump(tester);

    // `cdc` is the smallest set and is first-party, so it is the one engine
    // whose exact contents this repo controls.
    await tester.tap(find.widgetWithText(ChoiceChip, 'cdc'));
    await tester.pumpAndSettle();

    expect(find.text('cdc/per-bit-sync-bus'), findsOneWidget);
    expect(
      find.textContaining('verilator/'),
      findsNothing,
      reason:
          'the engine filter must exclude other engines, not just rank '
          'the chosen one first',
    );
  });

  testWidgets('search matches rule ids and tags', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _pump(tester);

    await tester.enterText(find.byType(TextField), 'per-bit');
    await tester.pumpAndSettle();
    expect(find.text('cdc/per-bit-sync-bus'), findsOneWidget);

    // Tags are searchable because a user auditing a category arrives holding
    // the category, not a rule name.
    await tester.enterText(find.byType(TextField), 'metastability');
    await tester.pumpAndSettle();
    expect(find.textContaining('cdc/'), findsWidgets);
  });

  testWidgets('tapping a rule filters the violations table to it', (
    tester,
  ) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The docs promised this before it existed: "Click a rule to filter the
    // table to it." The browser answers "what can this engine report"; the
    // next question is "and did it, here".
    final container = ProviderContainer();
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => container.read(ruleDatabaseProvider.future));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(body: RulesPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'per-bit-sync-bus');
    await tester.pumpAndSettle();
    await tester.tap(find.text('cdc/per-bit-sync-bus'));
    await tester.pumpAndSettle();

    expect(
      container.read(violationTableStateProvider).ruleSubstring,
      'cdc/per-bit-sync-bus',
      reason: 'the namespaced id scopes the table filter to exactly this rule',
    );
  });

  testWidgets(
    'the rule list is one Tab stop and the arrow keys move along it',
    (
      tester,
    ) async {
      TestWidgetsFlutterBinding.ensureInitialized();
      // Several hundred rules at two Tab stops each put well over a thousand
      // stops between the filters and the violations table beside this panel.
      final handle = tester.ensureSemantics();
      final container = await _pump(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'cdc'));
      await tester.pumpAndSettle();
      final rules = container
          .read(ruleDatabaseProvider)
          .requireValue
          .rulesFor('cdc');
      expect(rules.length, greaterThan(1));

      bool isRow(FocusStop stop, Rule rule) =>
          stop.name == rule.id || stop.name.startsWith('${rule.id} ');
      List<FocusStop> rowStops(FocusWalk walk) => [
        for (final stop in walk.stops)
          if (rules.any((rule) => isRow(stop, rule))) stop,
      ];

      final before = await walkFocus(tester);
      expectCleanFocusWalk(before, context: 'rules panel');
      expect(rowStops(before), hasLength(1));
      expect(isRow(rowStops(before).single, rules.first), isTrue);

      Future<void> tabTo(Rule rule) async {
        for (var i = 0; i < 40 && !isRow(describeFocus(tester), rule); i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        expect(isRow(describeFocus(tester), rule), isTrue);
      }

      await tabTo(rules.first);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        isRow(describeFocus(tester), rules[1]),
        isTrue,
        reason: 'Down moves focus to the next rule',
      );

      // The Tab stop followed focus: coming back to the list lands on the
      // second rule, and the first is no longer a stop.
      final after = await walkFocus(tester);
      expect(rowStops(after), hasLength(1));
      expect(isRow(rowStops(after).single, rules[1]), isTrue);

      await tabTo(rules[1]);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(isRow(describeFocus(tester), rules.first), isTrue);
      handle.dispose();
    },
  );

  testWidgets('a query matching nothing says so', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'zzzz-no-such-rule');
    await tester.pumpAndSettle();
    // An empty list and "no matches" look identical, and only one of them
    // tells the user their query was the problem.
    expect(find.text('No rules match.'), findsOneWidget);
  });
}
