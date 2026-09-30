// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/violation_store.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';

import '../../support/stress_corpus.dart';

/// Index-integrity stress test.
///
/// Loads the 50K synthetic corpus and asserts the four pre-computed indices
/// (severity / engine / rule / file) stay correct — equal to a brute-force
/// linear scan — under wholesale replace, partial per-file replace, and
/// streaming append. A corrupted index (a dropped insert, a stale bucket)
/// fails loudly.

/// Brute-force grouping of [all] by a key extractor — the independent
/// oracle the store's indices are compared against.
Map<K, List<Violation>> _groupBy<K>(
  List<Violation> all,
  K Function(Violation) key,
) {
  final out = <K, List<Violation>>{};
  for (final v in all) {
    (out[key(v)] ??= <Violation>[]).add(v);
  }
  return out;
}

void _assertIndicesMatchBruteForce(InMemoryViolationStore store) {
  final all = store.all;

  void checkIndex<K>(
    Map<K, List<Violation>> index,
    K Function(Violation) key,
    String label,
  ) {
    final expected = _groupBy(all, key);
    expect(
      index.keys.toSet(),
      expected.keys.toSet(),
      reason: '$label index has the wrong key set',
    );
    var covered = 0;
    for (final entry in expected.entries) {
      final bucket = index[entry.key] ?? const <Violation>[];
      expect(
        bucket.length,
        entry.value.length,
        reason: '$label index bucket "${entry.key}" has the wrong count',
      );
      expect(
        bucket.toSet(),
        entry.value.toSet(),
        reason: '$label index bucket "${entry.key}" has the wrong contents',
      );
      covered += bucket.length;
    }
    expect(covered, all.length, reason: '$label index lost violations');
  }

  checkIndex(store.bySeverity, (v) => v.severity, 'severity');
  checkIndex(store.byEngine, (v) => v.engineId, 'engine');
  checkIndex(store.byRule, (v) => v.ruleId, 'rule');
  checkIndex(store.byFile, (v) => v.location.file, 'file');
}

void main() {
  late InMemoryViolationStore store;
  late List<Violation> corpus;

  setUp(() {
    store = InMemoryViolationStore();
    corpus = stressViolations(50000);
    for (final entry in groupByEngine(corpus).entries) {
      store.replaceFromEngine(entry.key, entry.value);
    }
  });

  tearDown(() async {
    await store.dispose();
  });

  test('loads the full 50K corpus', () {
    expect(store.all, hasLength(50000));
  });

  test('all four indices equal a brute-force scan after replaceFromEngine', () {
    _assertIndicesMatchBruteForce(store);
  });

  test(
    'matches the committed distribution meta (generator is byte-stable)',
    () {
      final meta = stressMeta(50000);
      final byEngineMeta = meta['byEngine'] as Map<String, dynamic>;
      expect(byEngineMeta['verilator'], store.byEngine['verilator']?.length);
      expect(meta['distinctFiles'], store.byFile.length);
    },
  );

  test('filter() equals a brute-force predicate scan over a random sweep', () {
    final rng = Random(0xF117E2);
    for (var i = 0; i < 25; i++) {
      // Random filter: a severity subset, an engine subset, and/or a rule
      // substring. (Glob is exercised via the by-file index assertions.)
      final severities = <Severity>{
        for (final s in Severity.values)
          if (rng.nextBool()) s,
      };
      final engines = <String>{
        for (final e in stressEngines)
          if (rng.nextBool()) e,
      };
      final needle = rng.nextBool() ? 'WIDTH' : null;
      final filter = ViolationFilter(
        severities: severities.isEmpty ? null : severities,
        engineIds: engines.isEmpty ? null : engines,
        ruleSubstring: needle,
      );

      final actual = store.filter(filter).toSet();
      final expected = store.all.where((v) {
        if (filter.severities != null &&
            !filter.severities!.contains(v.severity)) {
          return false;
        }
        if (filter.engineIds != null &&
            !filter.engineIds!.contains(v.engineId)) {
          return false;
        }
        if (needle != null &&
            !v.ruleId.toLowerCase().contains(needle.toLowerCase()) &&
            !v.message.toLowerCase().contains(needle.toLowerCase())) {
          return false;
        }
        return true;
      }).toSet();

      expect(
        actual,
        expected,
        reason:
            'filter sweep #$i diverged from brute force '
            '(sev=$severities engines=$engines needle=$needle)',
      );
    }
  });

  test('indices stay correct after replacePartialFromEngine', () {
    // Re-run verilator over a subset of its files with a fresh result set.
    final verilatorFiles = store.byEngine['verilator']!
        .map((v) => v.location.file)
        .toSet()
        .take(20)
        .toSet();
    final replacement = <Violation>[
      for (final f in verilatorFiles)
        Violation(
          engineId: 'verilator',
          ruleId: 'verilator/UNUSEDSIGNAL',
          severity: Severity.error,
          message: 'partial-replace marker',
          location: SourceLocation(file: f, line: 7, column: 1),
        ),
    ];
    store.replacePartialFromEngine('verilator', verilatorFiles, replacement);
    _assertIndicesMatchBruteForce(store);
  });

  test('indices stay correct after streaming append', () {
    store
      ..addStreaming(
        const Violation(
          engineId: 'slang',
          ruleId: 'slang/ImplicitConvert',
          severity: Severity.note,
          message: 'streamed',
          location: SourceLocation(
            file: '/proj/src/f0001.sv',
            line: 1,
            column: 1,
          ),
        ),
      )
      ..completeStreaming('slang');
    _assertIndicesMatchBruteForce(store);
  });
}
