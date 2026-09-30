// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/violation_store.dart';
import 'package:lintcrux/domain/interfaces/violation_transformer.dart';
import 'package:lintcrux/domain/models/baseline_violation.dart';
import 'package:lintcrux/domain/models/lint_baseline.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/verilator/verilator_parser.dart';
import 'package:lintcrux/services/sarif/streaming_sarif_reader.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';

import '../support/stress_corpus.dart';

/// Perf-regression harness for the parse / ingest / filter performance budgets.
///
/// Compile-time gated so the normal `flutter test` run skips it; enable
/// with the WaveCrux-style define:
///
///   flutter test --dart-define=RUN_BENCHMARKS=true test/perf/lint_perf_bench_test.dart
///
/// Each metric is the median of three runs against the deterministic stress
/// corpus. One JSON row per metric is appended to `build/perf/results.jsonl`
/// (gitignored). Record the hardware / build-mode in the run context when
/// comparing results across machines.
const bool _runBenchmarks = bool.fromEnvironment('RUN_BENCHMARKS');

const String _resultsPath = 'build/perf/results.jsonl';

/// Median wall-clock (ms) of [body] over three runs.
double _medianMs(void Function() body) {
  final samples = <int>[];
  for (var i = 0; i < 3; i++) {
    final sw = Stopwatch()..start();
    body();
    sw.stop();
    samples.add(sw.elapsedMicroseconds);
  }
  samples.sort();
  return samples[1] / 1000.0;
}

void _record(String metric, double valueMs, {Map<String, dynamic>? extra}) {
  final row = <String, dynamic>{
    'timestamp': DateTime.now().toUtc().toIso8601String(),
    'metric': metric,
    'median_ms': double.parse(valueMs.toStringAsFixed(3)),
    ...?extra,
  };
  File(_resultsPath)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('${jsonEncode(row)}\n', mode: FileMode.append);
  // A benchmark harness legitimately prints its results to the console.
  // ignore: avoid_print
  print('[perf] $metric: ${valueMs.toStringAsFixed(1)} ms');
}

void main() {
  group(
    'lint perf bench',
    () {
      test('parse + ingest 50K verilator violations (goal < 2 s)', () {
        final lines = stressEngineOutLines(50000);
        final parser = VerilatorParser(rootPath: '/proj');
        final ms = _medianMs(() {
          InMemoryViolationStore().replaceFromEngine(
            'verilator',
            parser.parse(lines),
          );
        });
        _record(
          'parse_ingest_50k_ms',
          ms,
          extra: <String, dynamic>{
            'goal_ms': 2000,
          },
        );
        expect(ms, lessThan(2000 * 3), reason: 'far past the soft budget');
      });

      test('streaming ingest 100K + peak RSS (goal < 1 GB)', () async {
        final doc = stressSarifDocument(100000);
        const reader = StreamingSarifReader();
        final rssBefore = ProcessInfo.currentRss;
        final sw = Stopwatch()..start();
        final report = await reader.readAll(
          Stream<List<int>>.value(utf8.encode(doc)),
        );
        sw.stop();
        final rssMb = ProcessInfo.currentRss / (1024 * 1024);
        final total = report.runs.fold<int>(
          0,
          (s, r) => s + r.violations.length,
        );
        expect(total, 100000);
        _record(
          'stream_ingest_100k_ms',
          sw.elapsedMicroseconds / 1000.0,
          extra: <String, dynamic>{
            'peak_rss_mb': double.parse(rssMb.toStringAsFixed(1)),
            'rss_growth_mb': double.parse(
              ((ProcessInfo.currentRss - rssBefore) / (1024 * 1024))
                  .toStringAsFixed(1),
            ),
            'goal_rss_mb': 1024,
          },
        );
      });

      test('filter + sort over 50K rows (goal < 100 ms)', () {
        final store = InMemoryViolationStore();
        for (final e in groupByEngine(stressViolations(50000)).entries) {
          store.replaceFromEngine(e.key, e.value);
        }
        final ms = _medianMs(() {
          final result = store.filter(
            const ViolationFilter(ruleSubstring: 'WIDTH'),
          )..sort((a, b) => a.location.file.compareTo(b.location.file));
          if (result.isEmpty) throw StateError('unexpected empty filter');
        });
        _record(
          'filter_sort_50k_ms',
          ms,
          extra: <String, dynamic>{
            'goal_ms': 100,
          },
        );
      });

      test('per-engine severity aggregation over 50K (diagnostics path)', () {
        final store = InMemoryViolationStore();
        final byEngine = groupByEngine(stressViolations(50000));
        for (final e in byEngine.entries) {
          store.replaceFromEngine(e.key, e.value);
        }
        final engineIds = byEngine.keys.toList();
        // Mirrors diagnostics_providers: per engine, tally severities. With
        // byEngineOf this is O(total) — reading store.byEngine[id] per engine
        // copied every engine's bucket on each access (O(engines × total)).
        final ms = _medianMs(() {
          var total = 0;
          for (final id in engineIds) {
            final counts = <Severity, int>{};
            for (final v in store.byEngineOf(id)) {
              counts[v.severity] = (counts[v.severity] ?? 0) + 1;
            }
            total += counts.values.fold(0, (a, b) => a + b);
          }
          if (total != store.count) throw StateError('lost rows: $total');
        });
        _record(
          'by_engine_aggregate_50k_ms',
          ms,
          extra: <String, dynamic>{'engines': engineIds.length},
        );
      });

      test('only-new derive over 50K rows, baseline 25K (goal < 100 ms)', () {
        final corpus = stressViolations(50000);
        final baseline = LintBaseline(
          baselineId: 'bench-baseline',
          createdAt: DateTime.now().toUtc(),
          projectPath: '/proj',
          frozenViolations: <BaselineViolation>[
            for (final v in corpus.take(25000))
              BaselineViolation.fromViolation(v, projectRoot: '/proj'),
          ],
        );

        // Cold path: the per-derive cost the FNV + cached-regex fix targets —
        // recompute every live violation's fingerprint and test it against the
        // baseline set. This is what ran on every filter keystroke.
        final coldMs = _medianMs(() {
          final fps = baseline.fingerprintSet;
          var kept = 0;
          for (final v in corpus) {
            final fp = BaselineFingerprint.forProject(
              ruleId: v.ruleId,
              filePath: v.location.file,
              message: v.message,
              projectRoot: '/proj',
            );
            if (!fps.contains(fp)) kept++;
          }
          if (kept <= 0 || kept > corpus.length) {
            throw StateError('unexpected onlyNew count: $kept');
          }
        });
        _record(
          'only_new_derive_cold_50k_ms',
          coldMs,
          extra: <String, dynamic>{'goal_ms': 100, 'baseline_frozen': 25000},
        );

        // Warm path: the provider's real memoized derive. After the first
        // pass, every keystroke reuses the per-instance fingerprint cache, so
        // repeat derives collapse to set lookups.
        final fps = baseline.fingerprintSet;
        for (final v in corpus) {
          baselineFingerprintFor(v, projectRoot: '/proj'); // prime the cache
        }
        final warmMs = _medianMs(() {
          var kept = 0;
          for (final v in corpus) {
            if (!fps.contains(
              baselineFingerprintFor(v, projectRoot: '/proj'),
            )) {
              kept++;
            }
          }
          if (kept <= 0 || kept > corpus.length) {
            throw StateError('unexpected onlyNew count: $kept');
          }
        });
        _record(
          'only_new_derive_warm_50k_ms',
          warmMs,
          extra: <String, dynamic>{'baseline_frozen': 25000},
        );
      });

      test('transformer pipeline over 50K violations (goal < 500 ms)', () {
        final corpus = stressViolations(50000);
        const transformer = CompositeViolationTransformer.empty;
        final ms = _medianMs(() {
          final out = <Violation>[
            for (final v in corpus) transformer.transform(v),
          ];
          if (out.length != corpus.length) throw StateError('lost rows');
        });
        _record(
          'transformer_50k_ms',
          ms,
          extra: <String, dynamic>{
            'goal_ms': 500,
          },
        );
      });
    },
    skip: _runBenchmarks
        ? false
        : 'perf benchmarks gated — pass --dart-define=RUN_BENCHMARKS=true',
  );
}
