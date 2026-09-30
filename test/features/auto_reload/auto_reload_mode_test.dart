// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/auto_reload/providers/auto_reload_controller.dart';

void main() {
  group('pendingReloadProvider', () {
    test('defaults to false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(pendingReloadProvider), isFalse);
    });

    test('markPending(true) flips the state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(pendingReloadProvider.notifier).markPending(pending: true);
      expect(container.read(pendingReloadProvider), isTrue);
    });

    test('markPending(false) resets the state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(pendingReloadProvider.notifier).markPending(pending: true);
      container
          .read(pendingReloadProvider.notifier)
          .markPending(pending: false);
      expect(container.read(pendingReloadProvider), isFalse);
    });
  });
}
