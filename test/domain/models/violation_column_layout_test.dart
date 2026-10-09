// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/violation_column_layout.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';
import 'package:lintcrux/services/persistence/violation_column_layout_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ViolationColumnLayout', () {
    final defaults = ViolationColumnLayout.defaults;
    // 100 px per unit of weight: the default weights total 12.6.
    const tableWidth = 1260.0;

    test('a missing or invalid weight takes its default', () {
      final layout = ViolationColumnLayout(const {
        ViolationTableColumn.rule: 4,
        ViolationTableColumn.file: double.nan,
        ViolationTableColumn.line: -1,
      });
      expect(layout.weights[ViolationTableColumn.rule], 4);
      expect(
        layout.weights[ViolationTableColumn.file],
        ViolationColumnLayout.defaultWeights[ViolationTableColumn.file],
      );
      expect(
        layout.weights[ViolationTableColumn.line],
        ViolationColumnLayout.defaultWeights[ViolationTableColumn.line],
      );
    });

    test('a drag moves width between the two neighbours only', () {
      final after = defaults.resize(ViolationTableColumn.rule, 100, tableWidth);
      final perPixel = defaults.totalWeight / tableWidth;
      expect(
        after.weights[ViolationTableColumn.rule],
        closeTo(
          defaults.weights[ViolationTableColumn.rule]! + 100 * perPixel,
          1e-9,
        ),
      );
      expect(
        after.weights[ViolationTableColumn.file],
        closeTo(
          defaults.weights[ViolationTableColumn.file]! - 100 * perPixel,
          1e-9,
        ),
      );
      expect(after.totalWeight, closeTo(defaults.totalWeight, 1e-9));
      for (final c in [
        ViolationTableColumn.severity,
        ViolationTableColumn.engine,
        ViolationTableColumn.line,
        ViolationTableColumn.message,
      ]) {
        expect(after.weights[c], defaults.weights[c]);
      }
    });

    test('neither neighbour shrinks below the minimum width', () {
      final after = defaults.resize(
        ViolationTableColumn.rule,
        100000,
        tableWidth,
      );
      final perPixel = defaults.totalWeight / tableWidth;
      expect(
        after.weights[ViolationTableColumn.file],
        closeTo(ViolationColumnLayout.minColumnWidth * perPixel, 1e-9),
      );
    });

    test('the last column has no divider to drag', () {
      expect(
        defaults.resize(ViolationTableColumn.message, 50, tableWidth),
        same(defaults),
      );
    });
  });

  group('ViolationColumnLayoutCodec', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('nothing stored reads as the defaults', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(
        await const ViolationColumnLayoutCodec().load(prefs),
        ViolationColumnLayout.defaults,
      );
    });

    test('round-trips every weight', () async {
      final prefs = await SharedPreferences.getInstance();
      const codec = ViolationColumnLayoutCodec();
      final layout = ViolationColumnLayout.defaults.resize(
        ViolationTableColumn.engine,
        30,
        1000,
      );
      await codec.save(prefs, layout);
      expect(await codec.load(prefs), layout);
    });

    test('malformed JSON reads as the defaults', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ViolationColumnLayoutCodec.prefsKey: '{not json',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(
        await const ViolationColumnLayoutCodec().load(prefs),
        ViolationColumnLayout.defaults,
      );
    });
  });
}
