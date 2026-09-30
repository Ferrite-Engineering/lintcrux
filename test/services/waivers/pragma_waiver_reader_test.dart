// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:collection';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/waivers/pragma_waiver_reader.dart';

class _MapReader implements LineReader {
  _MapReader(this.byFile);
  final Map<String, List<String>?> byFile;
  @override
  Future<List<String>?> readLines(String file) async => byFile[file];
}

void main() {
  group('PragmaWaiverReader.parseLines', () {
    test('captures a single lint_off..lint_on pair', () {
      const reader = PragmaWaiverReader();
      final waivers = reader.parseLines(
        file: '/a.sv',
        lines: const [
          'module top;',
          '  // verilator lint_off UNUSED',
          '  logic foo;',
          '  // verilator lint_on UNUSED',
          'endmodule',
        ],
      );
      expect(waivers, hasLength(1));
      final w = waivers.single;
      expect(w.ruleLocalId, 'UNUSED');
      expect(w.startLine, 2);
      expect(w.endLine, 4);
      expect(w.covers(3), isTrue);
      expect(w.covers(5), isFalse);
    });

    test('lint_off without a lint_on extends to end-of-file', () {
      const reader = PragmaWaiverReader();
      final waivers = reader.parseLines(
        file: '/a.sv',
        lines: const [
          '// verilator lint_off WIDTH',
          'line 2',
          'line 3',
        ],
      );
      expect(waivers, hasLength(1));
      expect(waivers.single.startLine, 1);
      expect(waivers.single.endLine, 3);
    });

    test('different rules have independent stacks', () {
      const reader = PragmaWaiverReader();
      final waivers = reader.parseLines(
        file: '/a.sv',
        lines: const [
          '// verilator lint_off A',
          '// verilator lint_off B',
          '// verilator lint_on A',
          '// verilator lint_on B',
        ],
      );
      expect(waivers, hasLength(2));
      final a = waivers.firstWhere((w) => w.ruleLocalId == 'A');
      final b = waivers.firstWhere((w) => w.ruleLocalId == 'B');
      expect(a.startLine, 1);
      expect(a.endLine, 3);
      expect(b.startLine, 2);
      expect(b.endLine, 4);
    });

    test('block comment form is recognized', () {
      const reader = PragmaWaiverReader();
      final waivers = reader.parseLines(
        file: '/a.sv',
        lines: const [
          '/* verilator lint_off CASEX */',
          'x',
          '/* verilator lint_on CASEX */',
        ],
      );
      expect(waivers, hasLength(1));
      expect(waivers.single.ruleLocalId, 'CASEX');
    });

    test('lint_on without a matching lint_off is ignored', () {
      const reader = PragmaWaiverReader();
      final waivers = reader.parseLines(
        file: '/a.sv',
        lines: const [
          '// verilator lint_on UNUSED',
        ],
      );
      expect(waivers, isEmpty);
    });

    test('nested lint_off for the same rule produces two ranges', () {
      const reader = PragmaWaiverReader();
      final waivers = reader.parseLines(
        file: '/a.sv',
        lines: const [
          '// verilator lint_off UNUSED', // 1
          'a', // 2
          '// verilator lint_off UNUSED', // 3 (closes previous at 2, re-opens at 3)
          'b', // 4
          '// verilator lint_on UNUSED', // 5 (closes second at 5)
        ],
      );
      expect(waivers, hasLength(2));
      expect(waivers[0].startLine, 1);
      expect(waivers[0].endLine, 2);
      expect(waivers[1].startLine, 3);
      expect(waivers[1].endLine, 5);
    });

    test('non-pragma lines are ignored', () {
      const reader = PragmaWaiverReader();
      final waivers = reader.parseLines(
        file: '/a.sv',
        lines: const [
          '// completely unrelated comment',
          'module foo; endmodule',
        ],
      );
      expect(waivers, isEmpty);
    });
  });

  group('PragmaWaiverReader.readFiles', () {
    test('aggregates waivers across multiple files', () async {
      final reader = PragmaWaiverReader(
        reader: _MapReader({
          '/a.sv': [
            '// verilator lint_off UNUSED',
            '// verilator lint_on UNUSED',
          ],
          '/b.sv': [
            '// verilator lint_off WIDTH',
            'x',
            '// verilator lint_on WIDTH',
          ],
        }),
      );
      final map = await reader.readFiles(['/a.sv', '/b.sv']);
      expect(map.waivers, hasLength(2));
    });

    test('silently skips missing files', () async {
      final reader = PragmaWaiverReader(
        reader: _MapReader({}),
      );
      final map = await reader.readFiles(['/missing.sv']);
      expect(map.waivers, isEmpty);
    });
  });

  group('LineRangeMap.matchFor', () {
    test('returns the matching waiver', () {
      const map = LineRangeMap([
        PragmaWaiver(
          file: '/a.sv',
          ruleLocalId: 'UNUSED',
          startLine: 5,
          endLine: 10,
        ),
      ]);
      final w = map.matchFor(
        file: '/a.sv',
        line: 7,
        ruleLocalId: 'UNUSED',
      );
      expect(w, isNotNull);
    });

    test('returns null for the wrong file', () {
      const map = LineRangeMap([
        PragmaWaiver(
          file: '/a.sv',
          ruleLocalId: 'UNUSED',
          startLine: 5,
          endLine: 10,
        ),
      ]);
      expect(
        map.matchFor(file: '/b.sv', line: 7, ruleLocalId: 'UNUSED'),
        isNull,
      );
    });

    test('returns null for the wrong rule', () {
      const map = LineRangeMap([
        PragmaWaiver(
          file: '/a.sv',
          ruleLocalId: 'UNUSED',
          startLine: 5,
          endLine: 10,
        ),
      ]);
      expect(
        map.matchFor(file: '/a.sv', line: 7, ruleLocalId: 'WIDTH'),
        isNull,
      );
    });

    test('returns null when the line is outside the range', () {
      const map = LineRangeMap([
        PragmaWaiver(
          file: '/a.sv',
          ruleLocalId: 'UNUSED',
          startLine: 5,
          endLine: 10,
        ),
      ]);
      expect(
        map.matchFor(file: '/a.sv', line: 11, ruleLocalId: 'UNUSED'),
        isNull,
      );
    });

    test('overlapping ranges: the first declared wins', () {
      const outer = PragmaWaiver(
        file: '/a.sv',
        ruleLocalId: 'UNUSED',
        startLine: 1,
        endLine: 50,
      );
      const inner = PragmaWaiver(
        file: '/a.sv',
        ruleLocalId: 'UNUSED',
        startLine: 10,
        endLine: 20,
      );
      const otherRule = PragmaWaiver(
        file: '/a.sv',
        ruleLocalId: 'WIDTH',
        startLine: 1,
        endLine: 50,
      );
      expect(
        const LineRangeMap([
          otherRule,
          outer,
          inner,
        ]).matchFor(file: '/a.sv', line: 15, ruleLocalId: 'UNUSED'),
        same(outer),
      );
      expect(
        const LineRangeMap([
          inner,
          outer,
        ]).matchFor(file: '/a.sv', line: 15, ruleLocalId: 'UNUSED'),
        same(inner),
      );
    });

    test('answers exactly as a scan of every waiver in declaration order', () {
      final rng = Random(0x9A7A);
      const rules = ['UNUSED', 'WIDTH', 'CASEX'];
      final waivers = <PragmaWaiver>[
        for (var i = 0; i < 400; i++)
          () {
            final start = rng.nextInt(300) + 1;
            return PragmaWaiver(
              file: '/src/f${rng.nextInt(12)}.sv',
              ruleLocalId: rules[rng.nextInt(rules.length)],
              startLine: start,
              endLine: start + rng.nextInt(40),
            );
          }(),
      ];
      PragmaWaiver? scan(String file, int line, String rule) {
        for (final w in waivers) {
          if (w.file == file && w.ruleLocalId == rule && w.covers(line)) {
            return w;
          }
        }
        return null;
      }

      final map = LineRangeMap(List<PragmaWaiver>.unmodifiable(waivers));
      var hits = 0;
      for (var i = 0; i < 5000; i++) {
        final file = '/src/f${rng.nextInt(14)}.sv'; // 12 and 13 have none
        final line = rng.nextInt(360) + 1;
        final rule = rules[rng.nextInt(rules.length)];
        final expected = scan(file, line, rule);
        if (expected != null) hits++;
        expect(
          map.matchFor(file: file, line: line, ruleLocalId: rule),
          same(expected),
          reason: 'query $i: $file:$line $rule',
        );
      }
      // Both answers are exercised, not just the null one.
      expect(hits, greaterThan(500));
    });

    // matchFor runs once per violation on every lint run, cache hits
    // included. Scanning every pragma per lookup measured ~130 ms per
    // 50,000 violations at 1,000 pragmas, growing linearly with the pragma
    // count; the map must read each pragma once, not once per lookup.
    test('reads each pragma once per map, not once per lookup', () {
      final waivers = _CountingList(<PragmaWaiver>[
        for (var i = 0; i < 1000; i++)
          PragmaWaiver(
            file: '/src/f${i % 100}.sv',
            ruleLocalId: 'UNUSED',
            startLine: i + 1,
            endLine: i + 1,
          ),
      ]);
      final map = LineRangeMap(waivers);
      for (var i = 0; i < 500; i++) {
        map.matchFor(
          file: '/src/f${i % 120}.sv',
          line: i + 1,
          ruleLocalId: i.isEven ? 'UNUSED' : 'WIDTH',
        );
      }
      expect(waivers.reads, lessThanOrEqualTo(waivers.length));
    });
  });
}

/// A list that counts element reads, so a test can tell one pass over the
/// pragmas from one pass per lookup without timing anything.
class _CountingList extends ListBase<PragmaWaiver> {
  _CountingList(this._inner);

  final List<PragmaWaiver> _inner;
  int reads = 0;

  @override
  int get length => _inner.length;

  @override
  set length(int value) => throw UnsupportedError('read-only');

  @override
  PragmaWaiver operator [](int index) {
    reads++;
    return _inner[index];
  }

  @override
  void operator []=(int index, PragmaWaiver value) =>
      throw UnsupportedError('read-only');
}
