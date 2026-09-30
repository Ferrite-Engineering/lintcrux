// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Deterministic, byte-stable generators for the large-scale stress corpus.
// Shared by the stress tests, the perf harness,
// and tool/generate_stress_fixtures.dart so the 50K/100K corpora are
// reproducible from a seed instead of committed as multi-MB binaries.
//
// Distribution is deliberately power-law-ish (a few hot files / rules carry
// most violations) to match real-world lint workloads, where the index
// selectivity that the stress tests exercise actually matters.
import 'dart:math';

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/run.dart';
import 'package:lintcrux/domain/models/sarif_report.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/sarif/sarif_writer.dart';

/// Default seed — keep stable so the corpus is byte-identical run to run.
const int kStressSeed = 0x5712E55;

/// Engines represented in the multi-engine synthetic corpus.
const List<String> stressEngines = <String>[
  'verilator',
  'verible',
  'slang',
  'ghdl',
  'svlint',
];

const Map<String, List<String>> _rulesByEngine = <String, List<String>>{
  'verilator': <String>['UNUSEDSIGNAL', 'WIDTH', 'CASEINCOMPLETE', 'BLKSEQ'],
  'verible': <String>['no-tabs', 'line-length', 'no-trailing-spaces'],
  'slang': <String>['ImplicitConvert', 'WidthTruncate', 'UnusedButSet'],
  'ghdl': <String>['unused', 'hide', 'binding'],
  'svlint': <String>['tab_character', 'keyword_forbidden_wire_reg'],
};

const List<Severity> _severities = <Severity>[
  Severity.error,
  Severity.warning,
  Severity.warning,
  Severity.warning,
  Severity.note,
];

/// Number of distinct source files the corpus spreads across.
const int _fileCount = 500;

// A power-law-ish non-negative int in [0, bound): squaring a uniform
// [0,1) biases toward low indices (a few hot buckets).
int _powerLawIndex(Random rng, int bound) {
  final u = rng.nextDouble();
  return (u * u * bound).floor().clamp(0, bound - 1);
}

String _fileFor(int idx) => '/proj/src/f${idx.toString().padLeft(4, '0')}.sv';

/// Generates [count] synthetic violations spread across [stressEngines],
/// rules, files, and severities with a power-law distribution. Byte-stable
/// for a given [seed].
List<Violation> stressViolations(int count, {int seed = kStressSeed}) {
  final rng = Random(seed);
  final out = <Violation>[];
  for (var i = 0; i < count; i++) {
    final engine = stressEngines[_powerLawIndex(rng, stressEngines.length)];
    final rules = _rulesByEngine[engine]!;
    final rule = rules[rng.nextInt(rules.length)];
    final fileIdx = _powerLawIndex(rng, _fileCount);
    final severity = _severities[rng.nextInt(_severities.length)];
    out.add(
      Violation(
        engineId: engine,
        ruleId: '$engine/$rule',
        severity: severity,
        message: 'stress violation $i ($engine/$rule)',
        location: SourceLocation(
          file: _fileFor(fileIdx),
          line: rng.nextInt(2000) + 1,
          column: rng.nextInt(80) + 1,
        ),
      ),
    );
  }
  return out;
}

/// Groups [violations] by engine into one [Run] per engine — the shape the
/// store ingests via `replaceFromEngine`.
Map<String, List<Violation>> groupByEngine(List<Violation> violations) {
  final byEngine = <String, List<Violation>>{};
  for (final v in violations) {
    (byEngine[v.engineId] ??= <Violation>[]).add(v);
  }
  return byEngine;
}

/// Builds a compact SARIF document string carrying [count] violations
/// across one run per engine. Used by the streaming-reader stress test.
String stressSarifDocument(int count, {int seed = kStressSeed}) {
  final byEngine = groupByEngine(stressViolations(count, seed: seed));
  final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  final runs = <Run>[
    for (final entry in byEngine.entries)
      Run(
        id: 'stress/${entry.key}',
        engineId: entry.key,
        engineVersion: '',
        startedAt: epoch,
        finishedAt: epoch,
        violations: entry.value,
      ),
  ];
  return const SarifWriter(pretty: false).write(SarifReport(runs: runs));
}

/// Produces [count] verilator-style stderr lines (one violation each) for
/// the parse+ingest perf metric.
List<String> stressEngineOutLines(int count, {int seed = kStressSeed}) {
  final rng = Random(seed);
  final rules = _rulesByEngine['verilator']!;
  const severityWords = <String>['Error', 'Warning', 'Warning', 'Warning'];
  String line(int i) {
    final sev = severityWords[rng.nextInt(severityWords.length)];
    final rule = rules[rng.nextInt(rules.length)];
    final file = _fileFor(_powerLawIndex(rng, _fileCount));
    final ln = rng.nextInt(2000) + 1;
    final col = rng.nextInt(80) + 1;
    return '%$sev-$rule: $file:$ln:$col: stress diagnostic $i';
  }

  return <String>[for (var i = 0; i < count; i++) line(i)];
}

/// Exact counts of [stressViolations] of size [count], used to write and
/// pin `violations_50k.expected.meta.json`.
Map<String, dynamic> stressMeta(int count, {int seed = kStressSeed}) {
  final violations = stressViolations(count, seed: seed);
  final bySeverity = <String, int>{};
  final byEngine = <String, int>{};
  final byRule = <String, int>{};
  final byFile = <String, int>{};
  for (final v in violations) {
    bySeverity[v.severity.name] = (bySeverity[v.severity.name] ?? 0) + 1;
    byEngine[v.engineId] = (byEngine[v.engineId] ?? 0) + 1;
    byRule[v.ruleId] = (byRule[v.ruleId] ?? 0) + 1;
    byFile[v.location.file] = (byFile[v.location.file] ?? 0) + 1;
  }
  return <String, dynamic>{
    'seed': seed,
    'total': count,
    'distinctFiles': byFile.length,
    'bySeverity': bySeverity,
    'byEngine': byEngine,
    'distinctRules': byRule.length,
  };
}
