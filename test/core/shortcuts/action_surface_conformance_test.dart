// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Cross-surface conformance: every action-discovery surface (toolbar, menu
// bar, command palette) must render exactly the actions — and exactly the
// enabled/disabled state — that the single-source-of-truth selectors in
// `lintcrux_action_descriptors.dart` prescribe, across a matrix of contexts.
//
// Each surface reads the shared `lintcruxActionContextProvider`, so the
// harness overrides that provider with a precise `LintcruxActionContext` and
// asserts the rendered surface matches `groupedActionsFor` /
// `paletteActionsFor` / `isActionEnabled` for the same context. This keeps
// the assertions tied to the contract, not to any surface's internals.
//
// Adapted from WaveCrux's and NetCrux's equivalent guards (not copied
// verbatim — the surfaces, context provider, and action enum differ per
// product). Before this test, nothing in LintCrux verified that the menu
// bar, command palette, and toolbar actually rendered what
// `lintcrux_action_descriptors.dart` says they should — only that every
// action had *some* surface at all (`action_reachability_guard_test.dart`),
// never that a given surface's *rendering* matched the table.

import 'package:crux_command_palette/crux_command_palette.dart';
import 'package:crux_toolbar/crux_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/shortcuts/action_label.dart';
import 'package:lintcrux/core/shortcuts/action_tier_label.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_context.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_descriptor.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_descriptors.dart';
import 'package:lintcrux/features/command_palette/widgets/command_palette_dialog.dart';
import 'package:lintcrux/features/menu_bar/widgets/desktop_menu_bar.dart';
import 'package:lintcrux/features/workspace/providers/lintcrux_action_context_provider.dart';
import 'package:lintcrux/features/workspace/widgets/lintcrux_toolbar.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

void _noop(LintcruxAction _) {}

/// The context matrix every surface is checked against — representative of
/// LintCrux's real states, walking through every gate the descriptor table's
/// enablement predicates read (`_requiresTab`, `_requiresProject`,
/// `_canStartRun` / `_requiresRunInProgress`, `_requiresViolations`,
/// `_requiresSelectedViolation`, the pane/tab-count gates).
const Map<String, LintcruxActionContext> _contextMatrix = {
  'empty workspace': LintcruxActionContext(),
  'tab, no project': LintcruxActionContext(hasOpenTab: true),
  'project loaded, no violations': LintcruxActionContext(
    hasOpenTab: true,
    hasProject: true,
  ),
  'run in progress': LintcruxActionContext(
    hasOpenTab: true,
    hasProject: true,
    runInProgress: true,
  ),
  'violations, no selection': LintcruxActionContext(
    hasOpenTab: true,
    hasProject: true,
    hasViolations: true,
  ),
  'violations + selection': LintcruxActionContext(
    hasOpenTab: true,
    hasProject: true,
    hasViolations: true,
    hasSelectedViolation: true,
  ),
  'split panes, multiple tabs': LintcruxActionContext(
    hasOpenTab: true,
    hasProject: true,
    hasViolations: true,
    hasSelectedViolation: true,
    paneCount: 2,
    tabCountInActivePane: 3,
  ),
};

Widget _wrap({
  required Widget home,
  required LintcruxActionContext ctx,
  Locale? locale,
  TargetPlatform platform = TargetPlatform.macOS,
}) => ProviderScope(
  overrides: [lintcruxActionContextProvider.overrideWithValue(ctx)],
  child: MaterialApp(
    theme: ThemeData(platform: platform),
    locale: locale,
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: home,
  ),
);

List<PlatformMenuItem> _leafItems(PlatformMenuBar bar) {
  final result = <PlatformMenuItem>[];
  void visit(PlatformMenuItem item) {
    if (item is PlatformMenu) {
      item.menus.forEach(visit);
    } else if (item is PlatformMenuItemGroup) {
      item.members.forEach(visit);
    } else {
      result.add(item);
    }
  }

  bar.menus.forEach(visit);
  return result;
}

String _menuLabel(LintcruxAction a, L10N l10n) =>
    a.label(l10n) + tierLabelSuffix(a.requiredTier, l10n);

void main() {
  // ── Menu bar (native, desktop) ─────────────────────────────────────────
  group('DesktopMenuBar conformance', () {
    Future<(PlatformMenuBar, L10N)> pumpMenu(
      WidgetTester tester,
      LintcruxActionContext ctx,
    ) async {
      await tester.pumpWidget(
        _wrap(
          ctx: ctx,
          home: const DesktopMenuBar(
            onAction: _noop,
            child: Scaffold(body: SizedBox.shrink()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
      final l10n = L10N.of(tester.element(find.byType(PlatformMenuBar)));
      return (bar, l10n);
    }

    for (final entry in _contextMatrix.entries) {
      testWidgets('presence + enablement match the table (${entry.key})', (
        tester,
      ) async {
        final ctx = entry.value;
        final (bar, l10n) = await pumpMenu(tester, ctx);
        final expected = groupedActionsFor(
          LintcruxActionSurface.menu,
          ctx,
        ).values.expand((x) => x).toList();

        // Presence: the leaf labels are exactly the table's menu actions
        // (with tier suffixes). The edition-line statement item would also
        // be a leaf, but it renders only under a licensed tier and the
        // default `licenseStatusProvider` here is open-core (null line), so
        // it never contributes an extra leaf.
        expect(
          _leafItems(bar).map((e) => e.label).toSet(),
          expected.map((a) => _menuLabel(a, l10n)).toSet(),
        );

        // Enablement: a menu item is enabled iff the table says so.
        final leafByLabel = {for (final i in _leafItems(bar)) i.label: i};
        for (final a in expected) {
          final item = leafByLabel[_menuLabel(a, l10n)];
          expect(item, isNotNull, reason: '$a missing from menu');
          expect(
            item!.onSelected != null,
            isActionEnabled(a, ctx),
            reason: '$a enablement mismatch under "${entry.key}"',
          );
        }
      });
    }
  });

  // ── Command palette ──────────────────────────────────────────────────────
  group('CommandPaletteDialog conformance', () {
    for (final entry in _contextMatrix.entries) {
      testWidgets('listed actions match paletteActionsFor (${entry.key})', (
        tester,
      ) async {
        final ctx = entry.value;
        await tester.pumpWidget(
          _wrap(
            ctx: ctx,
            home: const Scaffold(body: CommandPaletteDialog(onAction: _noop)),
          ),
        );
        await tester.pumpAndSettle();
        final palette = tester.widget<CommandPalette<LintcruxAction>>(
          find.byType(CommandPalette<LintcruxAction>),
        );
        expect(
          palette.actions,
          paletteActionsFor(ctx),
          reason:
              'the palette must list exactly the visible+enabled actions '
              'under "${entry.key}"',
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('disabled and hidden actions never surface as rows', (
      tester,
    ) async {
      const ctx = LintcruxActionContext();
      await tester.pumpWidget(
        _wrap(
          ctx: ctx,
          home: const Scaffold(body: CommandPaletteDialog(onAction: _noop)),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = L10N.of(
        tester.element(find.byType(CommandPalette<LintcruxAction>)),
      );
      for (final hidden in [
        LintcruxAction.runAllEngines, // disabled: no project
        LintcruxAction.setBaseline, // structurally hidden: needs violations
        LintcruxAction.openCommandPalette, // self-referential
      ]) {
        expect(
          find.descendant(
            of: find.byType(CommandPalette<LintcruxAction>),
            matching: find.text(hidden.label(l10n)),
          ),
          findsNothing,
          reason: '$hidden must not render a palette row',
        );
      }
    });
  });

  // ── Toolbar ───────────────────────────────────────────────────────────────
  group('LintcruxToolbar conformance', () {
    // These are the only exemptions from the direct `ValueKey<LintcruxAction>`
    // presence check below, each for a structural reason (not an oversight):
    const runStopHandled = {
      LintcruxAction.runAllEngines,
      LintcruxAction.cancelRun,
    };
    const exportSiblingsInMenu = {
      LintcruxAction.exportJson,
      LintcruxAction.exportCsv,
      LintcruxAction.exportHtml,
    };
    Iterable<LintcruxAction> toolbarActions() => LintcruxAction.values.where(
      (a) => descriptorFor(a).surfaces.contains(LintcruxActionSurface.toolbar),
    );

    for (final entry in _contextMatrix.entries) {
      testWidgets(
        'every visible toolbar action has a button enabled per the table '
        '(${entry.key})',
        (tester) async {
          final ctx = entry.value;
          await tester.pumpWidget(
            _wrap(
              ctx: ctx,
              // Wide enough that nothing spills into the overflow menu —
              // the strip's default test-window width overflows and would
              // otherwise hide the run/stop control and the export cluster
              // from the tree entirely (mirrors `lintcrux_toolbar_test.dart`).
              home: const Scaffold(
                body: SizedBox(width: 1400, child: LintcruxToolbar()),
              ),
            ),
          );
          // The running state wears an indeterminate progress ring that
          // animates forever — `pumpAndSettle` would time out waiting for
          // it, so a single `pump` is enough to settle the initial frame.
          await tester.pump();

          for (final a in toolbarActions()) {
            if (runStopHandled.contains(a) ||
                exportSiblingsInMenu.contains(a)) {
              continue;
            }
            final keyFinder = find.byKey(ValueKey<LintcruxAction>(a));
            if (!isActionVisibleIn(a, LintcruxActionSurface.toolbar, ctx)) {
              expect(keyFinder, findsNothing, reason: '$a must be hidden');
              continue;
            }
            expect(keyFinder, findsOneWidget, reason: '$a button missing');
            // `CruxToolbarButton` itself carries `ValueKey<A>(action)` (see
            // `crux_toolbar.dart`'s `_render`), so the keyed widget IS the
            // button — no need to reach through a wrapper.
            final button = tester.widget<CruxToolbarButton>(keyFinder);
            expect(
              button.onPressed != null,
              isActionEnabled(a, ctx),
              reason: '$a enablement mismatch under "${entry.key}"',
            );
          }

          // The reverse direction. `LintcruxToolbar` places its buttons by
          // hand, so a button for an action whose descriptor does not claim
          // the toolbar passes the loop above, and the table then
          // under-reports where the action can be reached from.
          final rendered = tester
              .widgetList(
                find.descendant(
                  of: find.byType(LintcruxToolbar),
                  matching: find.byWidgetPredicate(
                    (w) => w.key is ValueKey<LintcruxAction>,
                  ),
                ),
              )
              .map((w) => (w.key! as ValueKey<LintcruxAction>).value)
              .toSet();
          expect(
            rendered,
            isNotEmpty,
            reason: 'no keyed toolbar button found — the check is vacuous',
          );
          expect(
            rendered.difference(toolbarActions().toSet()),
            isEmpty,
            reason:
                'LintcruxToolbar renders a button for an action whose '
                'descriptor does not list the toolbar surface',
          );

          // The run/stop control is a single morphing button rather than a
          // `ValueKey<LintcruxAction>`-keyed one (`CruxToolbarWidgetItem`
          // carries a plain string id), so its two actions are checked
          // directly against the widget's callbacks instead of by key.
          final runStop = tester.widget<CruxRunStopButton>(
            find.byType(CruxRunStopButton),
          );
          expect(
            runStop.onRun != null,
            isActionEnabled(LintcruxAction.runAllEngines, ctx),
            reason: 'runAllEngines enablement mismatch under "${entry.key}"',
          );
          expect(
            runStop.onCancel != null,
            isActionEnabled(LintcruxAction.cancelRun, ctx),
            reason: 'cancelRun enablement mismatch under "${entry.key}"',
          );
        },
      );
    }
  });

  // ── Locale sweep ────────────────────────────────────────────────────────
  group('locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('palette + toolbar render in $locale without exceptions', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            ctx: _contextMatrix['split panes, multiple tabs']!,
            locale: locale,
            home: const Scaffold(
              body: Column(
                children: [
                  LintcruxToolbar(),
                  Expanded(child: CommandPaletteDialog(onAction: _noop)),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
