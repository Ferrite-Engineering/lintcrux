// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/violations/violation_table_sort_order_test.dart
//
// Sort-order contract for the violation table header: tapping a column
// header (`ViolationTableHeader`'s `InkWell(onTap: () =>
// notifier.cycleSort(col))`) cycles `ViolationTableNotifier.cycleSort`,
// which flips `ViolationTableState.sortColumn` / `sortAscending` and
// re-derives `visibleViolationsProvider`. This asserts both the
// provider-level order AND the on-screen row order change together —
// same boot → fixture → seed scaffolding as
// `violation_table_journey_test.dart`.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  disablePlatformSemantics();

  testWidgets(
    'violation-table sort order: header tap cycles sort and reorders rows',
    (tester) async {
      // Seeding the violation table trips the debug-only first-build
      // provider self-invalidation wart (PENDING.md "Known issues"). It
      // can land on a frame after the triggering line, so filter it at
      // the source rather than reaching for `takeException` later.
      tolerateKnownFirstBuildWart();
      final projectDir = Directory.systemTemp.createTempSync(
        'lintcrux_vt_sort',
      );
      addTearDown(() {
        try {
          projectDir.deleteSync(recursive: true);
        } on FileSystemException {
          // Best-effort cleanup.
        }
      });

      await bootLintcrux(tester);
      final projectPath = await createFixtureProject(
        projectDir,
        sources: {
          'rtl/top.sv': '// fixture\nmodule top; wire unused_sig; endmodule\n',
          'rtl/util.sv': '// fixture\nmodule util_mod; endmodule\n',
        },
      );
      final tab = await openFixtureProject(tester, projectPath);
      expect(visibleViolations(tab), isEmpty);

      // Three violations whose rule ids sort in a distinct alphabetical
      // order (D < P < U) from the table's default severity sort, so a
      // sort-by-rule cycle visibly reorders the rows.
      const unusedLine =
          '%Warning-UNUSEDSIGNAL: rtl/top.sv:2:18: '
          "Signal is not used: 'unused_sig'";
      const declLine =
          '%Warning-DECLFILENAME: rtl/util.sv:2:8: '
          'Filename does not match module name';
      final violations = parseVerilatorFixture(projectDir.path, [
        unusedLine,
        '%Error-PINMISSING: rtl/top.sv:2:1: Cell pin is not connected: foo',
        declLine,
      ]);
      expect(violations, hasLength(3));
      await seedLintRun(tester, tab, violations: violations);
      final allSeeded = await pumpUntil(
        tester,
        () => visibleViolations(tab).length == 3,
      );
      expect(allSeeded, isTrue, reason: 'seeded violations never rendered');

      double dyOf(String ruleId) => tester.getTopLeft(find.text(ruleId)).dy;

      // 1. Tap the rule-column header. A new column always sorts
      // ascending first.
      await tester.tap(find.byKey(const ValueKey('violationTableHeader-rule')));
      final ascActive = await pumpUntil(
        tester,
        () =>
            tab.read(violationTableStateProvider).sortColumn ==
                ViolationTableColumn.rule &&
            tab.read(violationTableStateProvider).sortAscending,
      );
      expect(ascActive, isTrue, reason: 'header tap never activated rule sort');
      await tester.pump();
      expect(
        visibleViolations(tab).map((v) => v.ruleId).toList(),
        [
          'verilator/DECLFILENAME',
          'verilator/PINMISSING',
          'verilator/UNUSEDSIGNAL',
        ],
        reason: 'ascending rule sort did not reorder the provider list',
      );
      expect(
        dyOf('verilator/DECLFILENAME'),
        lessThan(dyOf('verilator/PINMISSING')),
      );
      expect(
        dyOf('verilator/PINMISSING'),
        lessThan(dyOf('verilator/UNUSEDSIGNAL')),
      );

      // 2. Tap the same header again: flips to descending.
      await tester.tap(find.byKey(const ValueKey('violationTableHeader-rule')));
      final descActive = await pumpUntil(
        tester,
        () =>
            tab.read(violationTableStateProvider).sortColumn ==
                ViolationTableColumn.rule &&
            !tab.read(violationTableStateProvider).sortAscending,
      );
      expect(
        descActive,
        isTrue,
        reason: 'second header tap never flipped to descending',
      );
      await tester.pump();
      expect(
        visibleViolations(tab).map((v) => v.ruleId).toList(),
        [
          'verilator/UNUSEDSIGNAL',
          'verilator/PINMISSING',
          'verilator/DECLFILENAME',
        ],
        reason: 'descending rule sort did not reverse the provider list',
      );
      expect(
        dyOf('verilator/UNUSEDSIGNAL'),
        lessThan(dyOf('verilator/PINMISSING')),
      );
      expect(
        dyOf('verilator/PINMISSING'),
        lessThan(dyOf('verilator/DECLFILENAME')),
      );

      expect(tester.takeException(), isNull);
    },
  );
}
