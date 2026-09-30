// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/lintcrux_tab_payload.dart';
import 'package:lintcrux/domain/models/session/lintcrux_session.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';

void main() {
  group('LintcruxTabPayload', () {
    test('constructs with defaults', () {
      const payload = LintcruxTabPayload(projectPath: '/p/a.lintcrux');
      expect(payload.projectPath, '/p/a.lintcrux');
      expect(payload.selectedRuleId, isNull);
      expect(payload.activeSeverities, isEmpty);
      expect(payload.activeEngineIds, isEmpty);
      expect(payload.ruleSubstring, '');
      expect(payload.fileGlob, '');
      expect(payload.sortColumn, ViolationTableColumn.severity);
      expect(payload.sortAscending, isTrue);
      expect(payload.savedFilterPresetName, isNull);
      expect(payload.viewMode, ViewMode.table);
      expect(payload.sessionExportPath, isNull);
    });

    test('equality compares every field including unordered sets', () {
      const a = LintcruxTabPayload(
        projectPath: '/p/a.lintcrux',
        activeSeverities: {Severity.error, Severity.warning},
        activeEngineIds: {'verilator', 'verible'},
        ruleSubstring: 'unused',
        fileGlob: '**.sv',
        savedFilterPresetName: 'release',
        viewMode: ViewMode.detailFocused,
        sessionExportPath: '/exports/a.lintcrux-session',
      );
      const b = LintcruxTabPayload(
        projectPath: '/p/a.lintcrux',
        // Same set, different iteration order.
        activeSeverities: {Severity.warning, Severity.error},
        activeEngineIds: {'verible', 'verilator'},
        ruleSubstring: 'unused',
        fileGlob: '**.sv',
        savedFilterPresetName: 'release',
        viewMode: ViewMode.detailFocused,
        sessionExportPath: '/exports/a.lintcrux-session',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('copyWith replaces only requested fields', () {
      const base = LintcruxTabPayload(projectPath: '/p/a.lintcrux');
      final next = base.copyWith(
        selectedRuleId: 'verilator/UNUSED',
        sortAscending: false,
      );
      expect(next.projectPath, '/p/a.lintcrux');
      expect(next.selectedRuleId, 'verilator/UNUSED');
      expect(next.sortAscending, isFalse);
      expect(next.viewMode, base.viewMode);
    });

    test('fromSession mirrors every session field', () {
      const session = LintcruxSession(
        projectPath: '/p/b.lintcrux',
        selectedRuleId: 'verible/no-trailing-spaces',
        activeSeverities: {Severity.error},
        activeEngineIds: {'verible'},
        ruleSubstring: 'trailing',
        fileGlob: 'src/**',
        sortColumn: ViolationTableColumn.rule,
        sortAscending: false,
        savedFilterPresetName: 'style',
        viewMode: ViewMode.detailFocused,
      );
      final p = LintcruxTabPayload.fromSession(session);
      expect(p.projectPath, '/p/b.lintcrux');
      expect(p.selectedRuleId, 'verible/no-trailing-spaces');
      expect(p.activeSeverities, {Severity.error});
      expect(p.activeEngineIds, {'verible'});
      expect(p.ruleSubstring, 'trailing');
      expect(p.fileGlob, 'src/**');
      expect(p.sortColumn, ViolationTableColumn.rule);
      expect(p.sortAscending, isFalse);
      expect(p.savedFilterPresetName, 'style');
      expect(p.viewMode, ViewMode.detailFocused);
      // fromSession does not carry a session export path.
      expect(p.sessionExportPath, isNull);
    });

    test('toString contains projectPath for diagnostic readability', () {
      const payload = LintcruxTabPayload(projectPath: '/p/x.lintcrux');
      expect(payload.toString(), contains('/p/x.lintcrux'));
    });
  });
}
