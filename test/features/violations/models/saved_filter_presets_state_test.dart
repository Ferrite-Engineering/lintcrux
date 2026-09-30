// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/named_filter_preset.dart';
import 'package:lintcrux/features/violations/models/saved_filter_presets_state.dart';

void main() {
  group('SavedFilterPresetsState', () {
    test('empty has no presets and no active selection', () {
      expect(SavedFilterPresetsState.empty.presets, isEmpty);
      expect(SavedFilterPresetsState.empty.activePresetName, isNull);
      expect(SavedFilterPresetsState.empty.activePreset, isNull);
    });

    test('activePreset resolves the named preset when present', () {
      const a = NamedFilterPreset(name: 'a');
      const b = NamedFilterPreset(name: 'b');
      const s = SavedFilterPresetsState(
        presets: [a, b],
        activePresetName: 'b',
      );
      expect(s.activePreset, b);
    });

    test('activePreset returns null if active name does not resolve', () {
      const a = NamedFilterPreset(name: 'a');
      const s = SavedFilterPresetsState(
        presets: [a],
        activePresetName: 'stale',
      );
      expect(s.activePreset, isNull);
    });

    test('copyWith with clearActivePreset wipes the active name', () {
      const a = NamedFilterPreset(name: 'a');
      const s = SavedFilterPresetsState(
        presets: [a],
        activePresetName: 'a',
      );
      final cleared = s.copyWith(clearActivePreset: true);
      expect(cleared.activePresetName, isNull);
      expect(cleared.presets, [a]);
    });

    test('equality compares lists and active name', () {
      const a = NamedFilterPreset(name: 'a');
      const x = SavedFilterPresetsState(presets: [a], activePresetName: 'a');
      const y = SavedFilterPresetsState(presets: [a], activePresetName: 'a');
      expect(x, equals(y));
      expect(x.hashCode, y.hashCode);
    });
  });
}
