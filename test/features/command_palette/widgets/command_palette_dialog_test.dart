// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/shortcuts/action_label.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_context.dart';
import 'package:lintcrux/features/command_palette/widgets/command_palette_dialog.dart';
import 'package:lintcrux/features/workspace/providers/lintcrux_action_context_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/shared/widgets/lintcrux_feature_tier_badge.dart';

Widget _app({Locale? locale, ValueChanged<LintcruxAction>? onAction}) =>
    ProviderScope(
      overrides: [
        // The palette lists visible AND enabled actions, so it needs a
        // context where the gated ones are live — otherwise a Pro action
        // like setBaseline (which requires violations) never renders and
        // the badge assertions have nothing to find.
        lintcruxActionContextProvider.overrideWithValue(
          const LintcruxActionContext(
            hasOpenTab: true,
            hasProject: true,
            hasViolations: true,
            hasSelectedViolation: true,
            paneCount: 2,
            tabCountInActivePane: 2,
          ),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: CommandPaletteDialog(onAction: onAction ?? _noop),
        ),
      ),
    );

void _noop(LintcruxAction _) {}

L10N _l10nOf(WidgetTester tester) =>
    L10N.of(tester.element(find.byType(CommandPaletteDialog)));

void main() {
  group('CommandPaletteDialog tier badges', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders in ${locale.toLanguageTag()} without exceptions', (
        tester,
      ) async {
        await tester.pumpWidget(_app(locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a Pro action row renders a LintCruxFeatureTierBadge', (
      tester,
    ) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      // Filter down to a single Pro action so the (virtualized) list only
      // builds its row.
      final proLabel = LintcruxAction.setBaseline.label(_l10nOf(tester));
      await tester.enterText(find.byType(TextField), proLabel);
      await tester.pumpAndSettle();
      expect(find.byType(LintCruxFeatureTierBadge), findsWidgets);
    });

    testWidgets('a free (open-core) action row renders no tier badge', (
      tester,
    ) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      final freeLabel = LintcruxAction.openProject.label(_l10nOf(tester));
      await tester.enterText(find.byType(TextField), freeLabel);
      await tester.pumpAndSettle();
      // The trailingBuilder returns null for open-core tiers, so no badge
      // widget is built for a free action.
      expect(find.byType(LintCruxFeatureTierBadge), findsNothing);
    });
  });

  // Regression: typing a query and pressing Enter did nothing in
  // shipped desktop builds, because the engine that owns the focused field's
  // text-input connection translates the keystroke into a
  // `TextInputAction.done` on the *text-input channel* and the framework
  // never sees a `KeyDownEvent`. `tester.sendKeyEvent` delivers to the
  // framework only, which is why no widget test caught it — the done-action
  // path below is the one that reproduces the field report. The fix lives in
  // `crux_command_palette`; these pin the LintCrux wrapper to it, because
  // `CommandPaletteDialog` passes `onAction` straight through and a wrapper
  // that swallowed it would present identically to the user.
  group('CommandPaletteDialog Enter dispatch', () {
    testWidgets('the text-input done action dispatches the highlighted row', (
      tester,
    ) async {
      final dispatched = <LintcruxAction>[];
      await tester.pumpWidget(_app(onAction: dispatched.add));
      await tester.pumpAndSettle();

      final label = LintcruxAction.openProject.label(_l10nOf(tester));
      await tester.enterText(find.byType(TextField), label);
      await tester.pumpAndSettle();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(dispatched, [LintcruxAction.openProject]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a framework Enter key event dispatches the highlighted row', (
      tester,
    ) async {
      final dispatched = <LintcruxAction>[];
      await tester.pumpWidget(_app(onAction: dispatched.add));
      await tester.pumpAndSettle();

      final label = LintcruxAction.openProject.label(_l10nOf(tester));
      await tester.enterText(find.byType(TextField), label);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(dispatched, [LintcruxAction.openProject]);
      expect(tester.takeException(), isNull);
    });
  });
}
