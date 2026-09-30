// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_toolbar/crux_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/shortcuts/action_label.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_context.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_descriptor.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_descriptors.dart';
import 'package:lintcrux/features/workspace/providers/lintcrux_action_context_provider.dart';
import 'package:lintcrux/features/workspace/widgets/lintcrux_toolbar.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// A project open with violations and a selection — every descriptor gate the
/// toolbar reads is satisfied, so the buttons are live.
const _loaded = LintcruxActionContext(
  hasOpenTab: true,
  hasProject: true,
  hasViolations: true,
  hasSelectedViolation: true,
  paneCount: 2,
  tabCountInActivePane: 2,
);

const _running = LintcruxActionContext(
  hasOpenTab: true,
  hasProject: true,
  hasViolations: true,
  runInProgress: true,
);

Future<List<LintcruxAction>> _pump(
  WidgetTester tester, {
  LintcruxActionContext ctx = _loaded,
  Locale? locale,
  double width = 1400,
  // The running state wears an indeterminate progress ring, which animates
  // forever — `pumpAndSettle` would time out waiting for it.
  bool settle = true,
}) async {
  final dispatched = <LintcruxAction>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [lintcruxActionContextProvider.overrideWithValue(ctx)],
      child: MaterialApp(
        locale: locale ?? const Locale('en'),
        localizationsDelegates: const [
          L10N.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: Actions(
              actions: <Type, Action<Intent>>{
                ShortcutActionIntent: CallbackAction<ShortcutActionIntent>(
                  onInvoke: (intent) {
                    dispatched.add(intent.action);
                    return null;
                  },
                ),
              },
              child: const LintcruxToolbar(),
            ),
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return dispatched;
}

Set<LintcruxAction> _rendered(WidgetTester tester) => tester
    .widgetList<CruxToolbarButton>(find.byType(CruxToolbarButton))
    .where((b) => b.key is ValueKey<LintcruxAction>)
    .map((b) => (b.key! as ValueKey<LintcruxAction>).value)
    .toSet();

void main() {
  group('LintcruxToolbar', () {
    testWidgets('renders through the shared CruxToolbar', (tester) async {
      await _pump(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(CruxToolbar<LintcruxAction>), findsOneWidget);
    });

    testWidgets('leads with the canonical common block, in suite order', (
      tester,
    ) async {
      await _pump(tester);
      const common = [
        LintcruxAction.openProject,
        LintcruxAction.saveSession,
        LintcruxAction.closeActiveProject,
        LintcruxAction.focusSearch,
        LintcruxAction.openCrossProbePanel,
        LintcruxAction.openSettings,
      ];
      final xs = [
        for (final a in common)
          tester.getCenter(find.byKey(ValueKey<LintcruxAction>(a))).dx,
      ];
      expect(xs, orderedEquals(List<double>.from(xs)..sort()));
      for (final a in [
        LintcruxAction.openSources,
        LintcruxAction.openWorkspace,
        LintcruxAction.importSarif,
      ]) {
        expect(
          tester.getCenter(find.byKey(ValueKey<LintcruxAction>(a))).dx,
          greaterThan(xs.last),
          reason: '$a is app-specific and belongs after the section divider',
        );
      }
    });

    testWidgets('every rendered button declares the toolbar surface', (
      tester,
    ) async {
      await _pump(tester);
      for (final action in _rendered(tester)) {
        expect(
          descriptorFor(action).surfaces,
          contains(LintcruxActionSurface.toolbar),
          reason:
              '${action.name} has a toolbar button but its descriptor does '
              'not list LintcruxActionSurface.toolbar',
        );
      }
    });

    testWidgets('dispatches the matching action for each button', (
      tester,
    ) async {
      for (final action in [
        LintcruxAction.openProject,
        LintcruxAction.saveSession,
        LintcruxAction.closeActiveProject,
        LintcruxAction.focusSearch,
        LintcruxAction.openCrossProbePanel,
        LintcruxAction.openSettings,
        LintcruxAction.openSources,
        LintcruxAction.openWorkspace,
        LintcruxAction.importSarif,
      ]) {
        final dispatched = await _pump(tester);
        await tester.tap(find.byKey(ValueKey<LintcruxAction>(action)));
        await tester.pump();
        expect(
          dispatched,
          <LintcruxAction>[action],
          reason: 'tapping $action should dispatch it',
        );
      }
    });

    group('enablement — the gap this migration closed', () {
      testWidgets('greys the project-gated buttons on the empty canvas', (
        tester,
      ) async {
        // Before the descriptor table these were all live and silently did
        // nothing: the toolbar offered to run engines with no project open.
        await _pump(tester, ctx: const LintcruxActionContext());

        IconButton buttonFor(LintcruxAction a) => tester.widget<IconButton>(
          find.descendant(
            of: find.byKey(ValueKey<LintcruxAction>(a)),
            matching: find.byType(IconButton),
          ),
        );
        expect(buttonFor(LintcruxAction.openProject).onPressed, isNotNull);
        expect(buttonFor(LintcruxAction.saveSession).onPressed, isNull);
        expect(buttonFor(LintcruxAction.focusSearch).onPressed, isNull);
        expect(
          buttonFor(LintcruxAction.closeActiveProject).onPressed,
          isNull,
        );
      });
    });

    group('Open Source Files', () {
      IconButton buttonFor(WidgetTester tester, LintcruxAction a) =>
          tester.widget<IconButton>(
            find.descendant(
              of: find.byKey(ValueKey<LintcruxAction>(a)),
              matching: find.byType(IconButton),
            ),
          );

      testWidgets('has a button at all', (tester) async {
        // It did not. `LintcruxAction.openSources` and its l10n label both
        // existed, and NetCrux surfaces the equivalent, but LintCrux left
        // the action menu- and palette-only.
        await _pump(tester);
        expect(
          find.byKey(
            const ValueKey<LintcruxAction>(LintcruxAction.openSources),
          ),
          findsOneWidget,
        );
      });

      testWidgets('is live when the active tab has a project', (tester) async {
        await _pump(tester);
        expect(
          buttonFor(tester, LintcruxAction.openSources).onPressed,
          isNotNull,
        );
      });

      testWidgets('greys out with no active project', (tester) async {
        // Adding sources to nothing is meaningless: `_handleOpenSources`
        // bails to the `openSourcesNoActiveProject` snackbar. A live button
        // whose only outcome is explaining why it did nothing is the same
        // defect the toolbar migration removed everywhere else.
        await _pump(tester, ctx: const LintcruxActionContext());
        expect(buttonFor(tester, LintcruxAction.openSources).onPressed, isNull);
      });

      testWidgets('tracks hasProject, not merely hasOpenTab', (tester) async {
        // An open tab whose project failed to load must NOT enable it —
        // that is the state where the file rewrite has no target.
        await _pump(
          tester,
          ctx: const LintcruxActionContext(hasOpenTab: true),
        );
        expect(buttonFor(tester, LintcruxAction.openSources).onPressed, isNull);
      });

      testWidgets('carries the same glyph NetCrux uses', (tester) async {
        await _pump(tester);
        final icon = tester.widget<Icon>(
          find.descendant(
            of: find.byKey(
              const ValueKey<LintcruxAction>(LintcruxAction.openSources),
            ),
            matching: find.byType(Icon),
          ),
        );
        expect(icon.icon, Icons.note_add_outlined);
      });

      testWidgets('Open Workspace reads as a file action', (tester) async {
        // `Icons.workspaces_outlined` is the workspaces cluster mark and
        // reads as a mode toggle; the folder glyph keeps Open Project's
        // verb and changes only the noun.
        await _pump(tester);
        final icon = tester.widget<Icon>(
          find.descendant(
            of: find.byKey(
              const ValueKey<LintcruxAction>(LintcruxAction.openWorkspace),
            ),
            matching: find.byType(Icon),
          ),
        );
        expect(icon.icon, Icons.folder_special_outlined);
      });
    });

    group('the morphing run control', () {
      testWidgets('idle offers Run and never a simultaneous Cancel', (
        tester,
      ) async {
        await _pump(tester);
        expect(find.byIcon(Icons.play_arrow), findsOneWidget);
        expect(
          find.byIcon(Icons.stop),
          findsNothing,
          reason: 'Run and Cancel used to sit side by side, both always lit',
        );
      });

      testWidgets('running offers Cancel with a progress ring', (tester) async {
        await _pump(tester, ctx: _running, settle: false);
        expect(find.byIcon(Icons.stop), findsOneWidget);
        expect(find.byIcon(Icons.play_arrow), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });

      testWidgets('dispatches run when idle and cancel when running', (
        tester,
      ) async {
        var dispatched = await _pump(tester);
        await tester.tap(find.byIcon(Icons.play_arrow));
        await tester.pump();
        expect(dispatched, [LintcruxAction.runAllEngines]);

        dispatched = await _pump(tester, ctx: _running, settle: false);
        await tester.tap(find.byIcon(Icons.stop));
        await tester.pump();
        expect(dispatched, [LintcruxAction.cancelRun]);
      });
    });

    group('the grouped export button', () {
      testWidgets('occupies one slot, not four', (tester) async {
        await _pump(tester);
        expect(
          find.byType(CruxToolbarSplitButton<LintcruxAction>),
          findsOneWidget,
        );
        final rendered = _rendered(tester);
        expect(rendered, contains(LintcruxAction.exportSarif));
        expect(rendered, isNot(contains(LintcruxAction.exportJson)));
      });

      testWidgets('offers every format in its sibling menu', (tester) async {
        await _pump(tester);
        await tester.longPress(
          find.byKey(
            const ValueKey<LintcruxAction>(LintcruxAction.exportSarif),
          ),
        );
        await tester.pumpAndSettle();
        final l10n = L10N.of(tester.element(find.byType(LintcruxToolbar)));
        for (final a in [
          LintcruxAction.exportSarif,
          LintcruxAction.exportJson,
          LintcruxAction.exportCsv,
          LintcruxAction.exportHtml,
        ]) {
          expect(find.text(a.label(l10n)), findsWidgets, reason: '$a missing');
        }
      });
    });

    testWidgets('shows the overflow button only when the strip overflows', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.byIcon(Icons.more_vert), findsNothing);
      await _pump(tester, width: 240);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    group('locale sweep', () {
      for (final locale in const [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('zh'),
        Locale('ja'),
        Locale('ko'),
      ]) {
        testWidgets('renders in $locale without exceptions', (tester) async {
          await _pump(tester, locale: locale);
          expect(tester.takeException(), isNull);
          expect(find.byType(CruxToolbar<LintcruxAction>), findsOneWidget);
        });
      }
    });
  });
}
