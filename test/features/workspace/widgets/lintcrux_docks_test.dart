// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LOCALE_SWEEP_EXEMPT: pure layout/visibility regression test (restore bars
// appear for hidden regions and reopen them); renders icons and keys, no
// localized copy is asserted.
import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:crux_dock/crux_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:lintcrux/features/viewer/providers/right_dock_provider.dart';
import 'package:lintcrux/features/workspace/widgets/lintcrux_docks.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/remote/cxp/lintcrux_cxp_binding.dart';

import '../../../support/telemetry_test_store.dart';

void main() {
  Future<ProviderContainer> pump(WidgetTester tester) async {
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const LintcruxDockRestoreBars(
                  child: ColoredBox(
                    color: Colors.black,
                    child: Center(child: Text('CENTER')),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('each left restore icon reopens the dock on its own tab', (
    tester,
  ) async {
    // D36: the left bar listed only Rules, and its click never selected
    // `rules`, so it reopened the dock on Sources; Sources had no icon.
    final container = await pump(tester);
    container
        .read(panelLayoutProvider.notifier)
        .setRuleBrowserVisible(visible: false);
    await tester.pump();

    expect(find.byKey(const ValueKey('cruxDockRestore-sources')), findsOne);
    expect(find.byKey(const ValueKey('cruxDockRestore-rules')), findsOne);

    await tester.tap(find.byKey(const ValueKey('cruxDockRestore-rules')));
    await tester.pump();
    expect(container.read(leftDockTabProvider), 'rules');
    expect(container.read(panelLayoutProvider).ruleBrowserVisible, isTrue);

    container
        .read(panelLayoutProvider.notifier)
        .setRuleBrowserVisible(visible: false);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('cruxDockRestore-sources')));
    await tester.pump();
    expect(container.read(leftDockTabProvider), 'sources');
    expect(container.read(panelLayoutProvider).ruleBrowserVisible, isTrue);
  });

  testWidgets('the bottom restore icon reveals the Source tab', (tester) async {
    final container = await pump(tester);
    container.read(bottomDockTabProvider.notifier).select('crossProbe');
    container
        .read(panelLayoutProvider.notifier)
        .setRunLogVisible(visible: false);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('cruxDockRestore-source')));
    await tester.pump();
    expect(container.read(bottomDockTabProvider), 'source');
    expect(container.read(panelLayoutProvider).runLogVisible, isTrue);
  });

  testWidgets('a tab that appears in the bottom dock is auto-revealed', (
    tester,
  ) async {
    // D37: the bottom dock passed no onAutoReveal, so a Cross-Probe tab that
    // arrived there stayed behind Source.
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...telemetryDeclinedOverrides(),
          cruxCxpProductBindingProvider.overrideWithValue(kLintcruxCxpBinding),
          cruxCxpPeersProvider.overrideWithValue(const <PeerIdentity>[]),
          cruxCxpServerStatusProvider.overrideWithValue((
            running: false,
            port: null,
            problem: null,
          )),
          cruxCxpUnreachablePeersProvider.overrideWith(
            (_) => Stream<List<CxpDialFailure>>.value(const <CxpDialFailure>[]),
          ),
          cruxCxpRuntimeProvider.overrideWith((_) async => null),
        ],
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const LintcruxBottomDock();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    container.read(crossProbeDockRegionProvider.notifier).move('bottom');
    container
        .read(panelLayoutProvider.notifier)
        .setCrossProbeVisible(visible: true);
    await tester.pump();
    await tester.pump();

    expect(container.read(bottomDockTabProvider), kRightDockTabCrossProbe);
  });

  testWidgets('a bar appearing or vanishing keeps the wrapped layout mounted', (
    tester,
  ) async {
    // The wrapper used to pick a different widget type for each combination
    // of collapsed regions, so every dock toggle rebuilt the whole IDE layout
    // beneath it -- discarding the pane scope, dock scroll positions, and the
    // show/hide animation. Every transition below, including several regions
    // flipping in the same frame, must leave the child's element where it is.
    final container = await pump(tester);
    final notifier = container.read(panelLayoutProvider.notifier)
      ..setRuleBrowserVisible(visible: true)
      ..setViolationDetailsVisible(visible: true)
      ..setRunLogVisible(visible: true);
    await tester.pump();
    final center = tester.element(find.text('CENTER'));

    final combinations = [
      for (final left in [true, false])
        for (final right in [true, false])
          for (final bottom in [true, false]) (left, right, bottom),
    ];
    for (final (left, right, bottom) in [
      ...combinations,
      ...combinations.reversed,
    ]) {
      notifier
        ..setRuleBrowserVisible(visible: left)
        ..setViolationDetailsVisible(visible: right)
        ..setRunLogVisible(visible: bottom);
      await tester.pump();
      expect(
        find.byType(CruxDockRestoreBar),
        findsNWidgets([left, right, bottom].where((v) => !v).length),
      );
      expect(
        tester.element(find.text('CENTER')),
        same(center),
        reason: 'left=$left right=$right bottom=$bottom rebuilt the child',
      );
    }
  });
}
