// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Shared support for the engine-output corpus.
//
// Single source of truth for *how a committed `output.txt` is turned into
// the golden SARIF*, so the corpus generator (tool/generate_engine_corpus.dart)
// and the golden test (engine_golden_test.dart) cannot disagree: both
// import this file and call buildCorpusSarifMap(). The generator writes the
// result; the test compares against it.
import 'package:lintcrux/domain/models/run.dart';
import 'package:lintcrux/domain/models/sarif_report.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/ghdl/ghdl_parser.dart';
import 'package:lintcrux/services/engines/slang/slang_parser.dart';
import 'package:lintcrux/services/engines/svlint/svlint_parser.dart';
import 'package:lintcrux/services/engines/verible/verible_parser.dart';
import 'package:lintcrux/services/engines/verilator/verilator_parser.dart';
import 'package:lintcrux/services/engines/yosys/yosys_check_engine.dart';
import 'package:lintcrux/services/sarif/sarif_writer.dart';

/// The fixed project root every corpus fixture resolves relative paths
/// against. Using a constant keeps the golden `artifactLocation.uri`
/// values byte-stable across machines.
const String kCorpusRootPath = '/work';

/// Every engine id the corpus covers. The first five are the hand-rolled
/// parsers exercised by the fuzz sweep; `yosys` parses via the external
/// `crux_yosys` package and is golden-only (no fuzz entry).
const List<String> kCorpusEngineIds = <String>[
  'verilator',
  'verible',
  'slang',
  'ghdl',
  'svlint',
  'yosys',
];

/// Runs the parser selected by [engineId] over [lines], collecting both
/// the emitted violations and the unrecognized lines the log-and-continue
/// contract surfaced.
///
/// The entry point per engine matches production: Verilator/GHDL parse a
/// text stderr transcript; Verible/Slang/Svlint parse their JSON-line
/// output (with the built-in text fallback). Throws [ArgumentError] for an
/// unknown engine so a typo in the case table fails loudly.
({List<Violation> violations, List<String> notifications}) runEngineParser(
  String engineId,
  List<String> lines, {
  String rootPath = kCorpusRootPath,
}) {
  final notifications = <String>[];
  void onUnrecognized(String line) => notifications.add(line);

  final List<Violation> violations;
  switch (engineId) {
    case 'verilator':
      violations = VerilatorParser(
        rootPath: rootPath,
      ).parse(lines, onUnrecognized: onUnrecognized);
    case 'ghdl':
      violations = GhdlParser(
        rootPath: rootPath,
      ).parse(lines, onUnrecognized: onUnrecognized);
    case 'verible':
      violations = VeribleParser(
        rootPath: rootPath,
      ).parseJsonLines(lines, onUnrecognized: onUnrecognized);
    case 'slang':
      violations = SlangParser(
        rootPath: rootPath,
      ).parseJsonLines(lines, onUnrecognized: onUnrecognized);
    case 'svlint':
      violations = SvlintParser(
        rootPath: rootPath,
      ).parseJsonLines(lines, onUnrecognized: onUnrecognized);
    case 'yosys':
      // Yosys parses a whole stderr transcript (not line-by-line) via the
      // crux_yosys parser; it surfaces no log-and-continue notifications.
      violations = YosysCheckEngine().violationsFromStderr(lines.join('\n'));
    default:
      throw ArgumentError.value(engineId, 'engineId', 'no parser registered');
  }
  return (violations: violations, notifications: notifications);
}

/// Builds the golden SARIF document (as a plain map) for a single corpus
/// case: parses [lines] with the [engineId] parser, then lowers the
/// violations + unrecognized-line notifications to SARIF via [SarifWriter].
///
/// The run id is deterministic (`gen/<engineId>/<caseName>`) and the timestamps
/// are the Unix epoch so the document is byte-stable — the same `output.txt`
/// always produces the same golden. The engine version is intentionally empty
/// (version drift has its own tests); the writer omits the field.
Map<String, dynamic> buildCorpusSarifMap(
  String engineId,
  String caseName,
  List<String> lines, {
  String rootPath = kCorpusRootPath,
}) {
  final parsed = runEngineParser(engineId, lines, rootPath: rootPath);
  final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  final run = Run(
    id: 'gen/$engineId/$caseName',
    engineId: engineId,
    engineVersion: '',
    startedAt: epoch,
    finishedAt: epoch,
    violations: parsed.violations,
    notifications: parsed.notifications,
  );
  final report = SarifReport(runs: <Run>[run]);
  return const SarifWriter().toMap(report);
}
