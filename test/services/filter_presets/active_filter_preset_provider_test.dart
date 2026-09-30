// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/filter_preset.dart';
import 'package:lintcrux/services/filter_presets/active_filter_preset_provider.dart';

void main() {
  group('activeFilterPresetProvider', () {
    final fixedAt = DateTime.utc(2026);

    FilterPreset buildPreset(String id) {
      return FilterPreset(
        id: id,
        name: id,
        filterState: const <String, Object?>{},
        createdAt: fixedAt,
        updatedAt: fixedAt,
      );
    }

    test('initial state is null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(activeFilterPresetProvider), isNull);
    });

    test('activate sets the preset', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final preset = buildPreset('preset_x');
      container.read(activeFilterPresetProvider.notifier).activate(preset);
      expect(container.read(activeFilterPresetProvider), equals(preset));
    });

    test('activate(null) clears the preset', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final preset = buildPreset('preset_x');
      container.read(activeFilterPresetProvider.notifier).activate(preset);
      expect(container.read(activeFilterPresetProvider), isNotNull);
      container.read(activeFilterPresetProvider.notifier).activate(null);
      expect(container.read(activeFilterPresetProvider), isNull);
    });

    test('clear() is equivalent to activate(null)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final preset = buildPreset('preset_x');
      container.read(activeFilterPresetProvider.notifier).activate(preset);
      container.read(activeFilterPresetProvider.notifier).clear();
      expect(container.read(activeFilterPresetProvider), isNull);
    });

    test(
      'per-container isolation: overriding the notifier yields independent state',
      () {
        final containerA = ProviderContainer(
          overrides: [
            activeFilterPresetProvider.overrideWith(
              ActiveFilterPresetNotifier.new,
            ),
          ],
        );
        final containerB = ProviderContainer(
          overrides: [
            activeFilterPresetProvider.overrideWith(
              ActiveFilterPresetNotifier.new,
            ),
          ],
        );
        addTearDown(containerA.dispose);
        addTearDown(containerB.dispose);
        containerA
            .read(activeFilterPresetProvider.notifier)
            .activate(buildPreset('a'));
        expect(containerA.read(activeFilterPresetProvider)?.id, equals('a'));
        expect(containerB.read(activeFilterPresetProvider), isNull);
      },
    );
  });
}
