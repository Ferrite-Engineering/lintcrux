// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/violation_column_layout.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';
import 'package:lintcrux/features/violations/providers/violation_column_layout_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LintCrux's column set over `crux_table`'s model. The model's own rules (a
/// drag moves width between neighbours only, the minimum width, the last
/// column's missing divider, the codec's round trip) are proven in
/// `crux_table`; this pins what LintCrux declares on top of it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('violationTableColumns', () {
    final defaults = violationTableColumns.defaults;
    // 100 px per unit of weight: the default weights total 12.6.
    const tableWidth = 1260.0;

    test('every column is resizable, in table order, with Message last', () {
      expect(violationTableColumns.columns, ViolationTableColumn.values);
      expect(
        violationTableColumns.isLast(ViolationTableColumn.message),
        isTrue,
      );
      expect(defaults.totalWeight, closeTo(12.6, 1e-9));
    });

    test('a missing or invalid weight takes its default', () {
      final layout = ViolationColumnLayout(violationTableColumns, const {
        ViolationTableColumn.rule: 4,
        ViolationTableColumn.file: double.nan,
        ViolationTableColumn.line: -1,
      });
      expect(layout.weights[ViolationTableColumn.rule], 4);
      expect(
        layout.weights[ViolationTableColumn.file],
        violationTableColumns.defaultWeights[ViolationTableColumn.file],
      );
      expect(
        layout.weights[ViolationTableColumn.line],
        violationTableColumns.defaultWeights[ViolationTableColumn.line],
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
    });

    test('neither neighbour shrinks below the suite minimum width', () {
      final after = defaults.resize(
        ViolationTableColumn.rule,
        100000,
        tableWidth,
      );
      final perPixel = defaults.totalWeight / tableWidth;
      expect(violationTableColumns.minColumnWidth, 56);
      expect(
        after.weights[ViolationTableColumn.file],
        closeTo(violationTableColumns.minColumnWidth * perPixel, 1e-9),
      );
    });
  });

  group('the persisted widths', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('live under the key the product has always used', () {
      expect(
        kViolationColumnWeightsPrefsKey,
        'settings.violationColumnWeights',
      );
      expect(
        violationColumnLayout.codec.prefsKey,
        kViolationColumnWeightsPrefsKey,
      );
    });

    test('nothing stored reads as the defaults', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(
        await violationColumnLayout.codec.load(prefs),
        violationTableColumns.defaults,
      );
    });

    test('round-trips every weight', () async {
      final prefs = await SharedPreferences.getInstance();
      final codec = violationColumnLayout.codec;
      final layout = violationTableColumns.defaults.resize(
        ViolationTableColumn.engine,
        30,
        1000,
      );
      await codec.save(prefs, layout);
      expect(await codec.load(prefs), layout);
    });

    test('a document an earlier release wrote reads back unchanged', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kViolationColumnWeightsPrefsKey:
            '{"severity":1.0,"engine":1.5,"rule":2.6,"file":2.2,'
            '"line":0.8,"message":5.0}',
      });
      final prefs = await SharedPreferences.getInstance();
      final layout = await violationColumnLayout.codec.load(prefs);
      expect(layout.weights[ViolationTableColumn.engine], 1.5);
      expect(layout.weights[ViolationTableColumn.rule], 2.6);
    });

    test('malformed JSON reads as the defaults', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kViolationColumnWeightsPrefsKey: '{not json',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(
        await violationColumnLayout.codec.load(prefs),
        violationTableColumns.defaults,
      );
    });
  });
}
