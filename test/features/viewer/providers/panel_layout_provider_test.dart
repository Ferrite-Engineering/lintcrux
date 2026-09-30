// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/panel_layout_state.dart';
import 'package:lintcrux/features/viewer/providers/panel_layout_provider.dart';

void main() {
  group('panelLayoutProvider', () {
    test('starts at PanelLayoutState defaults', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(panelLayoutProvider), const PanelLayoutState());
    });

    test('toggleRuleBrowser flips the rule-browser visibility', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(panelLayoutProvider.notifier);
      final before = container.read(panelLayoutProvider);
      notifier.toggleRuleBrowser();
      final after = container.read(panelLayoutProvider);
      expect(after.ruleBrowserVisible, !before.ruleBrowserVisible);
      expect(after.violationDetailsVisible, before.violationDetailsVisible);
      expect(after.runLogVisible, before.runLogVisible);
    });

    test('toggleViolationDetails flips only the details visibility', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(panelLayoutProvider.notifier).toggleViolationDetails();
      expect(
        container.read(panelLayoutProvider).violationDetailsVisible,
        isFalse,
      );
    });

    test('toggleRunLog flips only the run-log visibility', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(panelLayoutProvider.notifier).toggleRunLog();
      expect(container.read(panelLayoutProvider).runLogVisible, isFalse);
    });

    test('setRuleBrowserVisible sets the value explicitly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(panelLayoutProvider.notifier)
          .setRuleBrowserVisible(visible: false);
      expect(
        container.read(panelLayoutProvider).ruleBrowserVisible,
        isFalse,
      );
    });

    test('setRuleBrowserWidth and friends persist size changes', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(panelLayoutProvider.notifier)
        ..setRuleBrowserWidth(240)
        ..setViolationDetailsWidth(320)
        ..setRunLogHeight(200);
      final s = container.read(panelLayoutProvider);
      expect(s.ruleBrowserWidth, 240);
      expect(s.violationDetailsWidth, 320);
      expect(s.runLogHeight, 200);
    });

    test('replace swaps the entire state — used by bootstrap hydration', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const hydrated = PanelLayoutState(
        ruleBrowserVisible: false,
        violationDetailsVisible: false,
        runLogVisible: false,
        ruleBrowserWidth: 200,
      );
      container.read(panelLayoutProvider.notifier).replace(hydrated);
      expect(container.read(panelLayoutProvider), hydrated);
    });

    test('replace is a no-op when state already equals the input', () {
      // Documents the no-op guard so a future change that drops it
      // breaks a test rather than silently re-emitting state.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      var rebuildCount = 0;
      container.listen<PanelLayoutState>(
        panelLayoutProvider,
        (_, _) => rebuildCount++,
      );
      container
          .read(panelLayoutProvider.notifier)
          .replace(const PanelLayoutState());
      expect(rebuildCount, 0);
    });
  });
}
