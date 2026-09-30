// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';

void main() {
  group('ViolationTableState', () {
    test('initial has no filters and severity-ascending sort', () {
      const s = ViolationTableState.initial;
      expect(s.severities, isEmpty);
      expect(s.engineIds, isEmpty);
      expect(s.ruleSubstring, '');
      expect(s.fileGlob, '');
      expect(s.sortColumn, ViolationTableColumn.severity);
      expect(s.sortAscending, isTrue);
      expect(s.selectedRuleIds, isEmpty);
    });

    test('toFilter() drops empty fields', () {
      const s = ViolationTableState.initial;
      final f = s.toFilter();
      expect(f.severities, isNull);
      expect(f.engineIds, isNull);
      expect(f.ruleSubstring, isNull);
      expect(f.fileGlob, isNull);
    });

    test('toFilter() preserves non-empty fields', () {
      const s = ViolationTableState(
        severities: {Severity.error},
        engineIds: {'verilator'},
        ruleSubstring: 'foo',
        fileGlob: '**/top.sv',
      );
      final f = s.toFilter();
      expect(f.severities, {Severity.error});
      expect(f.engineIds, {'verilator'});
      expect(f.ruleSubstring, 'foo');
      expect(f.fileGlob, '**/top.sv');
    });

    test('idOf produces a stable string for a violation', () {
      const v = Violation(
        engineId: 'e',
        ruleId: 'e/r',
        severity: Severity.warning,
        message: 'm',
        location: SourceLocation(file: '/a/b.sv', line: 7, column: 3),
      );
      expect(ViolationTableState.idOf(v), 'e/r@/a/b.sv:7:3');
    });

    test('copyWith updates fields independently', () {
      const s = ViolationTableState.initial;
      final next = s.copyWith(
        sortColumn: ViolationTableColumn.message,
        sortAscending: false,
      );
      expect(next.sortColumn, ViolationTableColumn.message);
      expect(next.sortAscending, isFalse);
      // Other fields unchanged.
      expect(next.severities, s.severities);
    });
  });
}
