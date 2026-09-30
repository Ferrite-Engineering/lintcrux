// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';

/// Complexity guard for [InMemoryViolationStore]'s bulk-replacement path.
///
/// `replaceFromEngine` runs on the UI isolate for every re-run and every
/// lint-cache hit. The secondary indices (severity / rule / file) are
/// shared across engines, so removing an engine's violations one at a
/// time — a bucket scan per removed row — is quadratic in the size of
/// the widest bucket. At 50K rows sharing a severity that measured ~49
/// seconds of frozen UI; batching removal into one pass per distinct
/// affected key brings it to ~10ms.
///
/// The worst case is deliberately degenerate: every violation shares one
/// severity, one rule, and one file, so all three secondary buckets hold
/// the whole corpus. That is the shape a single-engine run over one large
/// generated file produces.
///
/// **Why operation counts, not wall-clock.** This started life as a
/// timed benchmark (2s absolute budget + a wall-clock scaling ratio).
/// That made it a *measurement-under-contention* flake: the `flutter
/// test` parallel pool runs the ~20s resolved-AST scope-leak scanner
/// (`test/static/scope_leak_scanner.dart`) alongside it, and that CPU
/// spike intermittently tipped the ratio over threshold even though the
/// algorithm was unchanged. Widening the tolerance would have hidden real
/// regressions, so instead the guard now asserts on
/// [InMemoryViolationStore.lastRemovalScans] — a deterministic count of
/// the element visits the removal phase performs. Batched removal visits
/// each affected bucket element exactly once (`4·N` for the mono-bucket
/// shape: `_all` + three single-key buckets); a per-violation removal
/// loop rescans an aggregate bucket once per removed row (`~3·N²`). The
/// count is a property of the algorithm, not of the machine's load, so it
/// is contention-immune while still failing by orders of magnitude on a
/// quadratic regression. This mirrors how NetCrux's analysis-complexity
/// guards assert on visit counters rather than the clock.
List<Violation> _monoBucket(int count, String engineId) => <Violation>[
  for (var i = 0; i < count; i++)
    Violation(
      engineId: engineId,
      ruleId: '$engineId/SAME_RULE',
      severity: Severity.warning,
      message: 'violation $i',
      location: SourceLocation(
        file: '/proj/src/one_big_file.sv',
        line: i + 1,
        column: 1,
      ),
    ),
];

/// Performs one wholesale replacement of [count] rows by [count] fresh
/// rows and returns the number of removal-phase element visits the store
/// reported for it (deterministic, independent of machine load).
int _replacementScans(int count) {
  final store = InMemoryViolationStore()
    ..replaceFromEngine('e', _monoBucket(count, 'e'));
  final replacement = _monoBucket(count, 'e');
  store.replaceFromEngine('e', replacement);
  return store.lastRemovalScans;
}

void main() {
  group('replaceFromEngine complexity', () {
    test(
      '50K single-bucket replacement stays linear in removed-corpus size',
      () {
        const n = 50000;
        final scans = _replacementScans(n);

        // Batched removal visits `_all` (N) plus each of the three
        // single-key buckets (N each) exactly once: 4·N. A per-violation
        // removal loop would rescan an aggregate bucket once per removed
        // row — ~3·N², i.e. ~7.5e9 here, ~37,500x over this ceiling. The
        // `> 0` lower bound guards against a silently-disabled counter
        // making the ceiling vacuously true.
        expect(
          scans,
          greaterThan(0),
          reason: 'removal-scan counter never engaged — the guard is inert',
        );
        expect(
          scans,
          lessThanOrEqualTo(5 * n),
          reason:
              'replaceFromEngine visited $scans elements removing 50K rows '
              'sharing one severity/rule/file (linear batching visits ~4·N = '
              '${4 * n}). A count this far above N is the signature of a '
              'per-violation bucket scan — removals must be batched into one '
              'pass per distinct affected index key.',
        );
      },
    );

    test('removal cost grows sub-quadratically across a 4x size step', () {
      final small = _replacementScans(12500);
      final large = _replacementScans(50000);

      // Deterministic: linear batching gives exactly 4·N, so the ratio is
      // exactly 4.0 across a 4x step. Quadratic per-violation removal
      // gives 16x. A ceiling of 6 sits well clear of both — it passes the
      // linear implementation with margin and fails the quadratic one by
      // ~2.7x — and because the inputs are counts, not timings, no amount
      // of CPU contention can move it.
      expect(small, greaterThan(0), reason: 'small-case counter never engaged');
      final ratio = large / small;
      expect(
        ratio,
        lessThan(6),
        reason:
            'A 4x larger replacement visited ${ratio.toStringAsFixed(1)}x more '
            'elements ($small -> $large). Linear batched removal predicts '
            '~4x; ~16x is the quadratic per-violation removal loop.',
      );
    });
  });

  group('index consistency under randomized replacement', () {
    /// Every index must equal a brute-force regrouping of `all` — the
    /// property batched removal has to preserve. Batching removes by
    /// identity against a drop-set, so this also pins that two
    /// semantically equal violations are not collapsed into one removal.
    void assertIndicesAgreeWithAll(InMemoryViolationStore store) {
      final all = store.all;

      void check<K>(
        Map<K, List<Violation>> index,
        K Function(Violation) keyOf,
        String label,
      ) {
        final expected = <K, List<Violation>>{};
        for (final v in all) {
          (expected[keyOf(v)] ??= <Violation>[]).add(v);
        }
        expect(
          index.keys.toSet(),
          expected.keys.toSet(),
          reason: '$label index key set drifted from `all`',
        );
        var covered = 0;
        for (final entry in expected.entries) {
          final bucket = index[entry.key] ?? const <Violation>[];
          expect(
            bucket.length,
            entry.value.length,
            reason: '$label bucket "${entry.key}" has the wrong count',
          );
          covered += bucket.length;
        }
        expect(
          covered,
          all.length,
          reason: '$label index lost or duplicated violations',
        );
      }

      check(store.bySeverity, (v) => v.severity, 'severity');
      check(store.byEngine, (v) => v.engineId, 'engine');
      check(store.byRule, (v) => v.ruleId, 'rule');
      check(store.byFile, (v) => v.location.file, 'file');
    }

    test('holds across 200 randomized replace / partial-replace rounds', () {
      final rng = Random(0x11C3);
      const engines = <String>['verilator', 'verible', 'slang'];
      const files = <String>['/p/a.sv', '/p/b.sv', '/p/c.sv'];
      const severities = <Severity>[
        Severity.error,
        Severity.warning,
        Severity.note,
      ];

      Violation gen(String engine, int i) => Violation(
        engineId: engine,
        ruleId: '$engine/R${rng.nextInt(3)}',
        severity: severities[rng.nextInt(severities.length)],
        message: 'm$i',
        location: SourceLocation(
          file: files[rng.nextInt(files.length)],
          line: rng.nextInt(100) + 1,
          column: 1,
        ),
      );

      final store = InMemoryViolationStore();
      addTearDown(store.dispose);

      for (var round = 0; round < 200; round++) {
        final engine = engines[rng.nextInt(engines.length)];
        final batch = <Violation>[
          for (var i = 0; i < rng.nextInt(40); i++) gen(engine, i),
        ];
        if (rng.nextBool()) {
          store.replaceFromEngine(engine, batch);
        } else {
          final changed = <String>{
            for (var i = 0; i < rng.nextInt(3) + 1; i++)
              files[rng.nextInt(files.length)],
          };
          store.replacePartialFromEngine(
            engine,
            changed,
            batch.where((v) => changed.contains(v.location.file)).toList(),
          );
        }
        assertIndicesAgreeWithAll(store);
      }
    });

    test('equal-but-distinct violations are removed individually', () {
      final store = InMemoryViolationStore();
      addTearDown(store.dispose);

      // NOT const: const canonicalization would make both calls return
      // the same instance, which is exactly the aliasing this test
      // exists to rule out.
      // ignore: prefer_const_constructors
      Violation twin() => Violation(
        engineId: 'e',
        ruleId: 'e/R',
        severity: Severity.warning,
        message: 'identical text',
        location: const SourceLocation(file: '/p/a.sv', line: 1, column: 1),
      );

      // Two rows that compare equal but are distinct objects. Identity
      // removal must drop both; a value-equality drop would leave one
      // behind in `all` or strip both from a bucket in one pass.
      store.replaceFromEngine('e', <Violation>[twin(), twin()]);
      expect(store.count, 2);
      expect(store.bySeverity[Severity.warning]!.length, 2);

      store.replaceFromEngine('e', <Violation>[twin()]);
      expect(store.count, 1);
      expect(store.bySeverity[Severity.warning]!.length, 1);
      expect(store.byRule['e/R']!.length, 1);
      expect(store.byFile['/p/a.sv']!.length, 1);
    });
  });
}
