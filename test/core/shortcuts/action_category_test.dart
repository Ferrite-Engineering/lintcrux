// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/shortcuts/action_category.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_context.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_descriptor.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_descriptors.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

void main() {
  // The descriptor table replaced the old deny-set helpers
  // (kMenuHiddenActions / menuVisibleActions / groupedActions). These now
  // exercise the same invariants through `groupedActionsFor` /
  // `paletteActionsFor`, which additionally understand enablement.
  const loaded = LintcruxActionContext(
    hasOpenTab: true,
    hasProject: true,
    hasViolations: true,
    hasSelectedViolation: true,
    paneCount: 2,
    tabCountInActivePane: 2,
  );

  group('command-palette reachability (issue #38)', () {
    test('openCommandPalette is reachable from the menu (recovery path)', () {
      // Must stay menu-reachable so unbinding Cmd/Ctrl+Shift+P can never make
      // the palette permanently inaccessible.
      expect(
        isActionVisibleIn(
          LintcruxAction.openCommandPalette,
          LintcruxActionSurface.menu,
          loaded,
        ),
        isTrue,
      );
    });

    test('openCommandPalette is excluded from the palette itself', () {
      expect(
        paletteActionsFor(loaded),
        isNot(contains(LintcruxAction.openCommandPalette)),
      );
    });

    test('openCommandPalette is grouped under View in the menu', () {
      expect(
        groupedActionsFor(
          LintcruxActionSurface.menu,
          loaded,
        )[ActionCategory.view],
        contains(LintcruxAction.openCommandPalette),
      );
    });
  });

  group('groupedActionsFor', () {
    test('returns a key for every ActionCategory', () {
      final grouped = groupedActionsFor(LintcruxActionSurface.menu, loaded);
      for (final cat in ActionCategory.values) {
        expect(grouped.containsKey(cat), isTrue);
      }
    });

    test('groups actions to match their category', () {
      final grouped = groupedActionsFor(LintcruxActionSurface.menu, loaded);
      for (final entry in grouped.entries) {
        for (final action in entry.value) {
          expect(action.category, entry.key);
        }
      }
    });

    test('includes disabled actions — the menu greys them rather than '
        'making them vanish', () {
      const empty = LintcruxActionContext();
      final menu = groupedActionsFor(
        LintcruxActionSurface.menu,
        empty,
      ).values.expand((x) => x);
      expect(menu, contains(LintcruxAction.runAllEngines));
      expect(isActionEnabled(LintcruxAction.runAllEngines, empty), isFalse);
    });

    test('the palette omits disabled actions — it has no greyed state', () {
      const empty = LintcruxActionContext();
      expect(
        paletteActionsFor(empty),
        isNot(contains(LintcruxAction.runAllEngines)),
      );
    });
  });

  group('ActionCategoryLabel locale sweep', () {
    Future<L10N> loadLocale(WidgetTester tester, Locale locale) async {
      late L10N captured;
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: const [
            L10N.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: L10N.supportedLocales,
          home: Builder(
            builder: (context) {
              captured = L10N.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return captured;
    }

    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('resolves a non-empty label for every category in $locale', (
        tester,
      ) async {
        final l10n = await loadLocale(tester, locale);
        for (final cat in ActionCategory.values) {
          expect(cat.label(l10n), isNotEmpty);
        }
      });
    }
  });
}
