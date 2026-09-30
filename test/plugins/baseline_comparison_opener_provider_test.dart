// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/plugins/baseline_comparison_opener_provider.dart';

void main() {
  group('baselineComparisonOpenerProvider', () {
    test('open-core default is null, not a no-op callback', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Null is the signal the dispatcher needs to give the user
      // feedback instead of silently swallowing the activation.
      expect(container.read(baselineComparisonOpenerProvider), isNull);
    });

    testWidgets('Pro overlay-style override is invoked on read+call', (
      tester,
    ) async {
      var calls = 0;
      late BuildContext capturedContext;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baselineComparisonOpenerProvider.overrideWithValue(
              (_) {
                calls++;
              },
            ),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                capturedContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(capturedContext);
      container.read(baselineComparisonOpenerProvider)!(capturedContext);
      expect(calls, 1);
    });
  });
}
