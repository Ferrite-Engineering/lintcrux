// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';

/// Incremental-merge correctness: after a per-file
/// partial re-run of one engine, the four indices reflect *only* that
/// engine's bucket changing — other engines' violations are byte-identical,
/// and a filter over the merged store still equals a brute-force scan.

Violation _v(
  String engineId,
  String rule,
  String file,
  int line, {
  Severity severity = Severity.warning,
}) => Violation(
  engineId: engineId,
  ruleId: '$engineId/$rule',
  severity: severity,
  message: '$rule at $file:$line',
  location: SourceLocation(file: file, line: line, column: 1),
);

void main() {
  late InMemoryViolationStore store;
  // Two engines over two files each.
  final verilator = <Violation>[
    _v('verilator', 'UNUSEDSIGNAL', '/p/a.sv', 10),
    _v('verilator', 'WIDTH', '/p/a.sv', 20, severity: Severity.error),
    _v('verilator', 'UNUSEDSIGNAL', '/p/b.sv', 5),
  ];
  final verible = <Violation>[
    _v('verible', 'no-tabs', '/p/a.sv', 3),
    _v('verible', 'line-length', '/p/b.sv', 99),
  ];

  setUp(() {
    store = InMemoryViolationStore()
      ..replaceFromEngine('verilator', verilator)
      ..replaceFromEngine('verible', verible);
  });

  tearDown(() async => store.dispose());

  test('partial replace touches only the named engine bucket', () {
    final veribleBefore = List<Violation>.from(store.byEngine['verible']!);

    // Re-run verilator over just /p/a.sv with a new result set.
    final newA = <Violation>[
      _v('verilator', 'CASEINCOMPLETE', '/p/a.sv', 12, severity: Severity.note),
    ];
    store.replacePartialFromEngine('verilator', {'/p/a.sv'}, newA);

    // verible bucket is untouched (same violations, same order).
    expect(store.byEngine['verible'], veribleBefore);

    // verilator now has: the /p/b.sv survivor + the new /p/a.sv result.
    final vNow = store.byEngine['verilator']!;
    expect(vNow.map((v) => v.ruleId).toSet(), {
      'verilator/UNUSEDSIGNAL',
      'verilator/CASEINCOMPLETE',
    });
    expect(vNow.where((v) => v.location.file == '/p/a.sv'), hasLength(1));
    expect(vNow.where((v) => v.location.file == '/p/b.sv'), hasLength(1));
  });

  test('all four indices equal a brute-force scan after partial replace', () {
    store.replacePartialFromEngine(
      'verilator',
      {'/p/a.sv'},
      <Violation>[_v('verilator', 'BLKSEQ', '/p/a.sv', 7)],
    );

    final all = store.all;
    Map<K, Set<Violation>> brute<K>(K Function(Violation) key) {
      final out = <K, Set<Violation>>{};
      for (final v in all) {
        (out[key(v)] ??= <Violation>{}).add(v);
      }
      return out;
    }

    void check<K>(Map<K, List<Violation>> index, K Function(Violation) key) {
      final expected = brute(key);
      expect(index.keys.toSet(), expected.keys.toSet());
      for (final e in expected.entries) {
        expect(index[e.key]!.toSet(), e.value);
      }
    }

    check(store.bySeverity, (v) => v.severity);
    check(store.byEngine, (v) => v.engineId);
    check(store.byRule, (v) => v.ruleId);
    check(store.byFile, (v) => v.location.file);
  });

  test('partial replace with an empty set removes the engine violations '
      'on the changed files only', () {
    store.replacePartialFromEngine('verilator', {
      '/p/a.sv',
    }, const <Violation>[]);
    // /p/a.sv verilator violations gone; /p/b.sv survivor remains.
    final vNow = store.byEngine['verilator']!;
    expect(vNow, hasLength(1));
    expect(vNow.single.location.file, '/p/b.sv');
    // verible /p/a.sv violation is NOT removed (different engine).
    expect(
      store.byFile['/p/a.sv']!.map((v) => v.engineId),
      contains('verible'),
    );
  });
}
