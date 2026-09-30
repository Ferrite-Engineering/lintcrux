// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/interfaces/filter_preset_store.dart';
import 'package:lintcrux/domain/models/filter_preset.dart';
import 'package:lintcrux/services/filter_presets/builtin_presets.dart';

void main() {
  group('NoopFilterPresetStore', () {
    test('listAll returns the supplied built-ins unmodified', () async {
      final store = NoopFilterPresetStore(builtins: builtinFilterPresets());
      final presets = await store.listAll();
      expect(presets.length, equals(3));
      expect(presets[0].id, equals(kBuiltinAllViolationsPresetId));
      expect(presets[1].id, equals(kBuiltinErrorsOnlyPresetId));
      expect(presets[2].id, equals(kBuiltinNewViolationsPresetId));
      expect(presets.every((p) => p.builtin), isTrue);
    });

    test('listAll returns an unmodifiable list', () async {
      final store = NoopFilterPresetStore(builtins: builtinFilterPresets());
      final presets = await store.listAll();
      expect(
        () => presets.add(
          FilterPreset(
            id: 'x',
            name: 'X',
            filterState: const {},
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('addOrUpdate throws UnsupportedError', () async {
      final store = NoopFilterPresetStore(builtins: builtinFilterPresets());
      expect(
        () => store.addOrUpdate(
          FilterPreset(
            id: 'x',
            name: 'X',
            filterState: const {},
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('remove throws UnsupportedError', () async {
      final store = NoopFilterPresetStore(builtins: builtinFilterPresets());
      expect(
        () => store.remove('builtin_all_violations'),
        throwsUnsupportedError,
      );
    });

    test('changed stream is empty', () async {
      final store = NoopFilterPresetStore(builtins: builtinFilterPresets());
      final events = await store.changed.toList();
      expect(events, isEmpty);
    });

    test('accepts custom built-in list for tests', () async {
      final custom = <FilterPreset>[
        FilterPreset(
          id: 'custom_b',
          name: 'Custom Built-in',
          builtin: true,
          filterState: const {},
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      ];
      final store = NoopFilterPresetStore(builtins: custom);
      final presets = await store.listAll();
      expect(presets.length, equals(1));
      expect(presets.single.id, equals('custom_b'));
    });
  });
}
