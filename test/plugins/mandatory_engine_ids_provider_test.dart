// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/plugins/mandatory_engine_ids_provider.dart';

void main() {
  group('mandatoryEngineIdsProvider', () {
    test('open core mandates nothing', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(mandatoryEngineIdsProvider), isEmpty);
    });

    test('an overlay override is what the run pipeline reads', () {
      final container = ProviderContainer(
        overrides: [
          mandatoryEngineIdsProvider.overrideWithValue(
            const <String>['verilator', 'cdc'],
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container.read(mandatoryEngineIdsProvider),
        <String>['verilator', 'cdc'],
      );
    });
  });
}
