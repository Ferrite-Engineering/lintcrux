// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/violation_transformer.dart';
import 'package:lintcrux/plugins/extra_violation_transformers_provider.dart';
import 'package:lintcrux/services/transformers/severity_override_transformer.dart';

void main() {
  group('extraViolationTransformersProvider', () {
    test('open core contributes nothing', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(extraViolationTransformersProvider), isEmpty);
    });

    test('an overlay override is what the pipeline reads', () {
      const extra = SeverityOverrideTransformer(<String, Severity>{
        'verilator/WIDTH': Severity.error,
      });
      final container = ProviderContainer(
        overrides: [
          extraViolationTransformersProvider.overrideWithValue(
            const <ViolationTransformer>[extra],
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(extraViolationTransformersProvider), [extra]);
    });
  });
}
