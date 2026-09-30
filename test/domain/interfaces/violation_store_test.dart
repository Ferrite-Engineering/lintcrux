// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/violation_store.dart';

void main() {
  group('ViolationFilter', () {
    test('empty matches the documented "any" sentinel', () {
      const empty = ViolationFilter.empty;
      expect(empty.severities, isNull);
      expect(empty.engineIds, isNull);
      expect(empty.ruleSubstring, isNull);
      expect(empty.fileGlob, isNull);
      expect(empty.includeSuppressed, isFalse);
    });

    test('constructor — fields are stored as supplied', () {
      const f = ViolationFilter(
        severities: {Severity.warning, Severity.error},
        engineIds: {'verilator'},
        ruleSubstring: 'UNUSED',
        fileGlob: '**/*.v',
        includeSuppressed: true,
      );
      expect(f.severities, {Severity.warning, Severity.error});
      expect(f.engineIds, {'verilator'});
      expect(f.ruleSubstring, 'UNUSED');
      expect(f.fileGlob, '**/*.v');
      expect(f.includeSuppressed, isTrue);
    });
  });

  group('ViolationStoreEvent', () {
    test('sealed hierarchy covers replace / add / complete', () {
      const ViolationStoreEvent ev1 = EngineReplaced('verilator', 42);
      const ViolationStoreEvent ev3 = RunCompleted('verilator');
      expect(ev1, isA<EngineReplaced>());
      expect(ev3, isA<RunCompleted>());
      // Exhaustive switch — the sealed-class promise.
      String describe(ViolationStoreEvent e) => switch (e) {
        EngineReplaced(:final engineId, :final violationCount) =>
          '$engineId=$violationCount',
        ViolationAdded(:final violation) => 'added ${violation.ruleId}',
        RunCompleted(:final engineId) => 'done $engineId',
      };
      expect(describe(ev1), 'verilator=42');
      expect(describe(ev3), 'done verilator');
    });
  });
}
