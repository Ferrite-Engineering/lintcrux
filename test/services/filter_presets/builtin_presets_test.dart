// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/enums/violation_view_mode.dart';
import 'package:lintcrux/domain/interfaces/violation_store.dart';
import 'package:lintcrux/services/filter_presets/builtin_presets.dart';
import 'package:lintcrux/services/filter_presets/filter_preset_overlay.dart';

void main() {
  group('builtinFilterPresets', () {
    test('ships exactly three built-ins in the documented order', () {
      final builtins = builtinFilterPresets();
      expect(builtins.length, equals(3));
      expect(builtins[0].id, equals(kBuiltinAllViolationsPresetId));
      expect(builtins[1].id, equals(kBuiltinErrorsOnlyPresetId));
      expect(builtins[2].id, equals(kBuiltinNewViolationsPresetId));
    });

    test('every built-in carries the builtin flag', () {
      for (final preset in builtinFilterPresets()) {
        expect(
          preset.builtin,
          isTrue,
          reason: '${preset.id} must be marked builtin',
        );
      }
    });

    test('built-in sortOrders occupy the reserved 0–99 range', () {
      for (final preset in builtinFilterPresets()) {
        expect(
          preset.sortOrder,
          lessThan(100),
          reason: '${preset.id} sortOrder must be < 100',
        );
      }
    });

    test('returns a fresh list on each call so callers can mutate locally', () {
      final a = builtinFilterPresets();
      final b = builtinFilterPresets();
      expect(identical(a, b), isFalse);
      // ...but the contained presets are value-equal.
      expect(a, equals(b));
    });

    test('built-in IDs are recognized by isBuiltinFilterPresetId', () {
      expect(isBuiltinFilterPresetId(kBuiltinAllViolationsPresetId), isTrue);
      expect(isBuiltinFilterPresetId(kBuiltinErrorsOnlyPresetId), isTrue);
      expect(isBuiltinFilterPresetId(kBuiltinNewViolationsPresetId), isTrue);
      expect(isBuiltinFilterPresetId('user_authored_preset'), isFalse);
      expect(isBuiltinFilterPresetId(''), isFalse);
    });

    test('"All Violations" preset has an empty filter state', () {
      final preset = builtinFilterPresets().firstWhere(
        (p) => p.id == kBuiltinAllViolationsPresetId,
      );
      expect(preset.filterState, isEmpty);
    });

    test('"Errors Only" preset restricts to fatal + error severities', () {
      final preset = builtinFilterPresets().firstWhere(
        (p) => p.id == kBuiltinErrorsOnlyPresetId,
      );
      final overlay = overlayFilterPreset(
        preset: preset,
        baseFilter: ViolationFilter.empty,
        baseViewMode: ViolationViewMode.allViolations,
      );
      expect(
        overlay.effectiveFilter.severities,
        equals({Severity.fatal, Severity.error}),
      );
    });

    test('"New Violations" preset sets viewMode to onlyNew', () {
      final preset = builtinFilterPresets().firstWhere(
        (p) => p.id == kBuiltinNewViolationsPresetId,
      );
      expect(preset.filterState['viewMode'], equals('onlyNew'));
    });
  });
}
