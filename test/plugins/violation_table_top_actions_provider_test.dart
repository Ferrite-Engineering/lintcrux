// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/plugins/violation_table_top_actions_provider.dart';

void main() {
  group('violationTableTopActionsProvider', () {
    test('open-core default is an empty list', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final actions = container.read(violationTableTopActionsProvider);
      expect(actions, isEmpty);
    });

    test(
      'Pro overlay-style override returns the supplied builders in order',
      () {
        final builders = <ViolationTableTopActionBuilder>[
          (_, _) => const Icon(Icons.settings_backup_restore),
          (_, _) => const Icon(Icons.filter_alt),
          (_, _) => const Icon(Icons.bookmark),
        ];
        final container = ProviderContainer(
          overrides: [
            violationTableTopActionsProvider.overrideWithValue(builders),
          ],
        );
        addTearDown(container.dispose);

        final read = container.read(violationTableTopActionsProvider);
        expect(read, hasLength(3));
        expect(read, same(builders));
      },
    );
  });
}
