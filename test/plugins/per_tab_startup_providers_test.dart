// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/plugins/per_tab_startup_providers.dart';

void main() {
  group('perTabStartupProvidersProvider', () {
    test('open-core default is empty list', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final hooks = container.read(perTabStartupProvidersProvider);
      expect(hooks, isEmpty);
    });

    test('Pro overlay-style override surfaces the registered providers', () {
      final perTabListener = Provider<int>((_) => 3);
      final container = ProviderContainer(
        overrides: [
          perTabStartupProvidersProvider.overrideWithValue(
            <PerTabStartupHook>[perTabListener],
          ),
        ],
      );
      addTearDown(container.dispose);

      final hooks = container.read(perTabStartupProvidersProvider);
      expect(hooks, hasLength(1));
      expect(hooks.single, same(perTabListener));
      // `ProjectTabContent` subscribes to each entry on the TAB's own
      // container; the registration contract is what is under test here.
      // The per-tab invocation is covered by the Pro overlay's journeys,
      // which observe the listeners' side effects.
    });

    test('a tab-scoped child container resolves the root list', () {
      final perTabListener = Provider<int>((_) => 3);
      final root = ProviderContainer(
        overrides: [
          perTabStartupProvidersProvider.overrideWithValue(
            <PerTabStartupHook>[perTabListener],
          ),
        ],
      );
      addTearDown(root.dispose);
      final tab = ProviderContainer(parent: root);
      addTearDown(tab.dispose);

      // The list is root configuration: not re-bound per tab, so the
      // child container parent-delegates to the root registration.
      expect(tab.read(perTabStartupProvidersProvider), hasLength(1));
    });

    test('a tab-container subscription resolves the tab-scoped instance', () {
      // The seam is only useful if the subscription the host takes on the
      // tab's container resolves that tab's re-bound provider. A hook
      // whose provider is NOT re-bound per tab parent-delegates to the
      // single root instance and degenerates back to root scope.
      final perTab = Provider<String>((_) => 'root');
      final root = ProviderContainer();
      addTearDown(root.dispose);
      final tab = ProviderContainer(
        parent: root,
        overrides: [perTab.overrideWithValue('tab')],
      );
      addTearDown(tab.dispose);

      String? seen;
      final sub = tab.listen<Object?>(perTab, (_, _) {});
      seen = tab.read(perTab);
      addTearDown(sub.close);

      expect(seen, 'tab');
      expect(root.read(perTab), 'root');
    });
  });
}
