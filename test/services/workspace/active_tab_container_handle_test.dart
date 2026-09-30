// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/workspace/active_tab_container_handle.dart';

void main() {
  group('ActiveTabContainerHandle', () {
    test('activeContainer is null before any resolver is published', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final handle = container.read(activeTabContainerHandleProvider);
      expect(handle.resolver, isNull);
      expect(handle.activeContainer, isNull);
    });

    test('activeContainer delegates to the published resolver', () {
      final root = ProviderContainer();
      addTearDown(root.dispose);
      final tab = ProviderContainer(parent: root);
      addTearDown(tab.dispose);

      final handle = root.read(activeTabContainerHandleProvider)
        ..resolver = (() => tab);
      expect(handle.activeContainer, same(tab));

      // A resolver may legitimately report "no active tab".
      handle.resolver = () => null;
      expect(handle.activeContainer, isNull);

      // Clearing the resolver (WorkspaceRoot.dispose) reverts to null.
      handle.resolver = null;
      expect(handle.activeContainer, isNull);
    });

    test('the handle is a root singleton shared with tab containers', () {
      final root = ProviderContainer();
      addTearDown(root.dispose);
      final tab = ProviderContainer(parent: root);
      addTearDown(tab.dispose);

      expect(
        tab.read(activeTabContainerHandleProvider),
        same(root.read(activeTabContainerHandleProvider)),
      );
    });
  });
}
