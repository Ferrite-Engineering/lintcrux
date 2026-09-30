// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/session/lintcrux_session.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';

void main() {
  group('LintcruxSession serialization', () {
    test('round-trips a fully-populated session', () {
      const session = LintcruxSession(
        projectPath: '/work/proj.lintcrux',
        selectedRuleId: 'verilator/UNUSED',
        activeSeverities: {Severity.error, Severity.warning},
        activeEngineIds: {'verilator', 'verible'},
        ruleSubstring: 'unused',
        fileGlob: 'src/**/*.sv',
        sortColumn: ViolationTableColumn.rule,
        sortAscending: false,
        savedFilterPresetName: 'audit',
        viewMode: ViewMode.detailFocused,
      );
      final restored = LintcruxSession.fromJson(session.toJson());
      expect(restored.projectPath, session.projectPath);
      expect(restored.selectedRuleId, session.selectedRuleId);
      expect(restored.activeSeverities, session.activeSeverities);
      expect(restored.activeEngineIds, session.activeEngineIds);
      expect(restored.ruleSubstring, session.ruleSubstring);
      expect(restored.fileGlob, session.fileGlob);
      expect(restored.sortColumn, session.sortColumn);
      expect(restored.sortAscending, session.sortAscending);
      expect(restored.savedFilterPresetName, session.savedFilterPresetName);
      expect(restored.viewMode, session.viewMode);
    });

    test('default-shaped session round-trips', () {
      const session = LintcruxSession(projectPath: '/a.lintcrux');
      final restored = LintcruxSession.fromJson(session.toJson());
      expect(restored.projectPath, '/a.lintcrux');
      expect(restored.sortColumn, ViolationTableColumn.severity);
      expect(restored.sortAscending, isTrue);
      expect(restored.viewMode, ViewMode.table);
    });

    test('omits optional fields from JSON when null', () {
      const session = LintcruxSession(projectPath: '/a.lintcrux');
      final out = session.toJson();
      expect(out.containsKey('selectedRuleId'), isFalse);
      expect(out.containsKey('savedFilterPresetName'), isFalse);
    });

    test('throws when version is missing', () {
      expect(
        () => LintcruxSession.fromJson(const {'projectPath': '/x'}),
        throwsA(isA<LintcruxSessionLoadException>()),
      );
    });

    test('throws when version is newer than supported', () {
      expect(
        () => LintcruxSession.fromJson(const {
          'version': 999,
          'projectPath': '/x',
        }),
        throwsA(isA<LintcruxSessionLoadException>()),
      );
    });

    test('throws when projectPath is missing', () {
      expect(
        () => LintcruxSession.fromJson(const {'version': 1}),
        throwsA(isA<LintcruxSessionLoadException>()),
      );
    });

    test('silently drops unknown severity names', () {
      final loaded = LintcruxSession.fromJson(const {
        'version': 1,
        'projectPath': '/x',
        'activeSeverities': ['warning', 'invented'],
      });
      expect(loaded.activeSeverities, {Severity.warning});
    });

    test('falls back to severity sort column for an unknown value', () {
      final loaded = LintcruxSession.fromJson(const {
        'version': 1,
        'projectPath': '/x',
        'sortColumn': 'bogus',
      });
      expect(loaded.sortColumn, ViolationTableColumn.severity);
    });

    test('falls back to table view mode for an unknown value', () {
      final loaded = LintcruxSession.fromJson(const {
        'version': 1,
        'projectPath': '/x',
        'viewMode': 'bogus',
      });
      expect(loaded.viewMode, ViewMode.table);
    });
  });
}
