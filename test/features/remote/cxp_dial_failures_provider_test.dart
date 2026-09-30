// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/remote/providers/cxp_server_provider.dart';

void main() {
  group('cxpDialFailuresProvider', () {
    test('defaults to an empty snapshot', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(cxpDialFailuresProvider), isEmpty);
    });

    test('replace publishes the new snapshot', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const failure = CxpDialFailure(
        peerId: 'wavecrux-9',
        host: '127.0.0.1',
        port: 54399,
        error: 'Connection refused',
        consecutiveFailures: 2,
        nextRetryAfterTicks: 3,
      );
      container.read(cxpDialFailuresProvider.notifier).replace(const [failure]);

      final state = container.read(cxpDialFailuresProvider);
      expect(state, hasLength(1));
      expect(state.single.peerId, 'wavecrux-9');
    });

    test('published snapshot is unmodifiable', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(cxpDialFailuresProvider.notifier).replace(const [
        CxpDialFailure(
          peerId: 'p1',
          host: '127.0.0.1',
          port: 1,
          error: 'x',
          consecutiveFailures: 1,
          nextRetryAfterTicks: 0,
        ),
      ]);

      final state = container.read(cxpDialFailuresProvider);
      expect(
        () => state.add(
          const CxpDialFailure(
            peerId: 'p2',
            host: '127.0.0.1',
            port: 2,
            error: 'y',
            consecutiveFailures: 1,
            nextRetryAfterTicks: 0,
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('replace with an empty list clears a prior snapshot', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(cxpDialFailuresProvider.notifier)
        ..replace(const [
          CxpDialFailure(
            peerId: 'p1',
            host: '127.0.0.1',
            port: 1,
            error: 'x',
            consecutiveFailures: 1,
            nextRetryAfterTicks: 0,
          ),
        ]);
      expect(container.read(cxpDialFailuresProvider), isNotEmpty);

      notifier.replace(const []);
      expect(container.read(cxpDialFailuresProvider), isEmpty);
    });
  });
}
