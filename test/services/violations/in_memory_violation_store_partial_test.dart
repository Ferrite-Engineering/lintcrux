// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/violation_store.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';

Violation _v(
  String engineId,
  String rule, {
  String file = '/p/a.sv',
  int line = 1,
  Severity severity = Severity.warning,
}) => Violation(
  engineId: engineId,
  ruleId: '$engineId/$rule',
  severity: severity,
  message: 'msg',
  location: SourceLocation(file: file, line: line, column: 1),
);

void main() {
  group('InMemoryViolationStore.replacePartialFromEngine', () {
    test('preserves violations on unchanged files for the same engine', () {
      final store = InMemoryViolationStore()
        ..replaceFromEngine('verilator', [
          _v('verilator', 'UNUSED'),
          _v('verilator', 'WIDTHTRUNC', file: '/p/b.sv', line: 10),
        ])
        ..replacePartialFromEngine(
          'verilator',
          {'/p/a.sv'},
          [_v('verilator', 'UNUSED', line: 5)],
        );

      final byFile = store.byFile;
      expect(byFile.containsKey('/p/a.sv'), isTrue);
      expect(byFile.containsKey('/p/b.sv'), isTrue);
      expect(byFile['/p/a.sv']!.single.location.line, 5);
      expect(byFile['/p/b.sv']!.single.ruleId, 'verilator/WIDTHTRUNC');
    });

    test('replaces violations on changed files atomically', () {
      final store = InMemoryViolationStore()
        ..replaceFromEngine('verilator', [
          _v('verilator', 'UNUSED', line: 3),
          _v('verilator', 'UNUSED', line: 7),
        ])
        ..replacePartialFromEngine(
          'verilator',
          {'/p/a.sv'},
          [
            _v('verilator', 'UNUSED', line: 11),
            _v('verilator', 'WIDTHTRUNC', line: 20),
          ],
        );

      final lines = store.byFile['/p/a.sv']!
          .map((v) => v.location.line)
          .toList();
      expect(lines, containsAll(<int>[11, 20]));
      expect(lines, isNot(contains(3)));
      expect(lines, isNot(contains(7)));
    });

    test("does not touch other engines' violations", () {
      final store = InMemoryViolationStore()
        ..replaceFromEngine('verilator', [_v('verilator', 'UNUSED')])
        ..replaceFromEngine('verible', [_v('verible', 'STYLE')])
        ..replacePartialFromEngine(
          'verilator',
          {'/p/a.sv'},
          [_v('verilator', 'WIDTHTRUNC', line: 9)],
        );

      expect(store.byEngine['verilator'], hasLength(1));
      expect(
        store.byEngine['verilator']!.single.ruleId,
        'verilator/WIDTHTRUNC',
      );
      expect(store.byEngine['verible'], hasLength(1));
      expect(store.byEngine['verible']!.single.ruleId, 'verible/STYLE');
    });

    test("empty newViolations purges the engine's entries for those files", () {
      final store = InMemoryViolationStore()
        ..replaceFromEngine('verilator', [
          _v('verilator', 'UNUSED'),
          _v('verilator', 'UNUSED', file: '/p/b.sv'),
        ])
        ..replacePartialFromEngine('verilator', {'/p/a.sv'}, const []);

      expect(store.byFile.containsKey('/p/a.sv'), isFalse);
      expect(store.byFile.containsKey('/p/b.sv'), isTrue);
      expect(store.byEngine['verilator'], hasLength(1));
    });

    test('all indices stay in sync after partial replacement', () {
      final store = InMemoryViolationStore()
        ..replaceFromEngine('verilator', [
          _v('verilator', 'UNUSED', severity: Severity.note),
          _v(
            'verilator',
            'WIDTHTRUNC',
            file: '/p/b.sv',
            severity: Severity.error,
          ),
        ])
        ..replacePartialFromEngine(
          'verilator',
          {'/p/a.sv'},
          [_v('verilator', 'PINMISSING')],
        );

      expect(store.byRule.keys, contains('verilator/PINMISSING'));
      expect(store.byRule.keys, contains('verilator/WIDTHTRUNC'));
      expect(store.byRule.keys, isNot(contains('verilator/UNUSED')));

      expect(store.bySeverity[Severity.warning], hasLength(1));
      expect(store.bySeverity[Severity.error], hasLength(1));
      expect(store.bySeverity[Severity.note], isNull);
    });

    test('emits an EngineReplaced event with the new total', () async {
      final store = InMemoryViolationStore()
        ..replaceFromEngine('verilator', [
          _v('verilator', 'UNUSED'),
          _v('verilator', 'UNUSED', file: '/p/b.sv'),
        ]);
      final events = <ViolationStoreEvent>[];
      final sub = store.events.listen(events.add);

      store.replacePartialFromEngine(
        'verilator',
        {'/p/a.sv'},
        [_v('verilator', 'UNUSED', line: 4)],
      );
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(events, isNotEmpty);
      expect(events.first, isA<EngineReplaced>());
    });
  });
}
