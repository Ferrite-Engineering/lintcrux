// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Mutation proof for the code that maps a lint run to its outcome
// (`classifyLintRun`, contracts 11; standing rule 8).
//
// The oracle below states, from the contracts alone, what the `--json`
// document and the `lint` tool must say for a run in which an engine timed
// out, crashed or was missing: `engine_error` with the engine's own reason,
// `isError` over MCP, exit 3 on the command line, and the engine's run
// marked as it ended. The real mapping keeps the oracle on every case, at
// both doors. Two deliberately broken mappings (a timed-out engine called
// `completed`; any engine failure called `completed`) are run through the
// same pipeline, and the oracle must catch each on every case it breaks.

@TestOn('vm')
library;

import 'dart:convert';

import 'package:crux_mcp/crux_mcp.dart' hide HeadlessTelemetry;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/cli/lintcrux_cli.dart';
import 'package:lintcrux/domain/models/engine_run_outcome.dart';
import 'package:lintcrux/headless/lint_document.dart';
import 'package:lintcrux/services/headless/headless_run_result.dart';

import 'support/spec_cases.dart';
import 'support/spec_engines.dart';

/// Each scenario, the engine run the document must report, and the error
/// code that must say why.
const Map<SpecScenario, (String phase, bool timedOut, String code)> _expected =
    <SpecScenario, (String, bool, String)>{
      SpecScenario.timesOut: ('failed', true, 'engine.timeout'),
      SpecScenario.crashes: ('failed', false, 'engine.failed'),
      SpecScenario.missing: ('unavailable', false, 'engine.unavailable'),
    };

/// Every way [doc] (with [isError] from the tool result, or [exit] from the
/// command line) breaks the contract for a run of [scenario].
List<String> _oracle(
  SpecScenario scenario,
  Map<String, Object?> doc, {
  bool? isError,
  int? exit,
}) {
  final (phase, timedOut, code) = _expected[scenario]!;
  final problems = <String>[];
  if (doc['outcome'] != 'engine_error') {
    problems.add('outcome is ${doc['outcome']}, not engine_error');
  }
  if (isError != null && !isError) problems.add('isError is false');
  if (exit != null && exit != 3) problems.add('exit is $exit, not 3');
  final errors = <String>[
    for (final d
        in (doc['diagnostics']! as List<Object?>).cast<Map<String, Object?>>())
      if (d['severity'] == 'error') d['code']! as String,
  ];
  if (!errors.contains(code)) problems.add('no $code error in $errors');
  final body = doc['body'] as Map<String, Object?>?;
  final runs = (body?['engine_runs'] as List<Object?>? ?? const <Object?>[])
      .cast<Map<String, Object?>>();
  final verible = runs.where((r) => r['id'] == 'verible').toList();
  if (verible.length != 1) {
    problems.add('the verible run is not reported once');
  } else {
    if (verible.single['phase'] != phase) {
      problems.add('verible phase is ${verible.single['phase']}, not $phase');
    }
    if (verible.single['timed_out'] != timedOut) {
      problems.add('verible timed_out is ${verible.single['timed_out']}');
    }
  }
  return problems;
}

/// A mapping that calls a run with a timed-out engine `completed`.
LintClassification _timeoutIsCompleted(HeadlessRunResult result) =>
    result.engineOutcomes.containsValue(EngineRunOutcome.timeout)
    ? const LintClassification(McpOutcome.completed, <McpDiagnostic>[])
    : classifyLintRun(result);

/// A mapping that calls any run whose only problems are engines `completed`.
LintClassification _engineFailureIsCompleted(HeadlessRunResult result) =>
    result.failures.isNotEmpty &&
        result.failures.every((f) => f.kind == HeadlessFailureKind.engine)
    ? const LintClassification(McpOutcome.completed, <McpDiagnostic>[])
    : classifyLintRun(result);

void main() {
  final spec = SpecCases.load();
  tearDownAll(spec.dispose);
  final base = spec.cases.firstWhere((c) => c.golden == 'lint/completed.json');

  LintcruxCli cli(SpecScenario scenario, LintRunClassifier classify) =>
      LintcruxCli(
        registry: specRegistry(scenario),
        installSignalReaper: false,
        withheld: openCoreWithheld,
        mcpTelemetry: () => null,
        classify: classify,
      );

  /// The oracle's findings for [scenario] under [classify], at both doors.
  Future<List<String>> probe(
    SpecScenario scenario,
    LintRunClassifier classify,
  ) async {
    final result = await spec.callTool(cli(scenario, classify), base);
    final text =
        ((result['content']! as List<Object?>).single!
                as Map<String, Object?>)['text']!
            as String;
    final (stdoutText, exit) = await spec.runCommandLine(
      cli(scenario, classify),
      spec.argv(base),
    );
    return <String>[
      for (final problem in _oracle(
        scenario,
        jsonDecode(text) as Map<String, Object?>,
        isError: result['isError']! as bool,
      ))
        'mcp: $problem',
      for (final problem in _oracle(
        scenario,
        jsonDecode(stdoutText) as Map<String, Object?>,
        exit: exit,
      ))
        'cli: $problem',
    ];
  }

  group('the real mapping keeps the oracle', () {
    for (final scenario in _expected.keys) {
      test(scenario.name, () async {
        expect(await probe(scenario, classifyLintRun), isEmpty);
      });
    }
  });

  test('a mapping that calls a timed-out engine completed is caught', () async {
    final caught = await probe(SpecScenario.timesOut, _timeoutIsCompleted);
    expect(caught, contains('mcp: outcome is completed, not engine_error'));
    expect(caught, contains('mcp: isError is false'));
    expect(caught, contains('cli: outcome is completed, not engine_error'));
    // The mutant changes nothing else.
    expect(await probe(SpecScenario.crashes, _timeoutIsCompleted), isEmpty);
  });

  test('a mapping that calls any engine failure completed is caught on every '
      'kind of failure', () async {
    for (final scenario in _expected.keys) {
      expect(
        await probe(scenario, _engineFailureIsCompleted),
        contains('mcp: outcome is completed, not engine_error'),
        reason: scenario.name,
      );
    }
  });

  test(
    'the oracle is not vacuous: a clean run is not an engine error',
    () async {
      final result = await spec.callTool(
        cli(SpecScenario.ok, classifyLintRun),
        base,
      );
      final text =
          ((result['content']! as List<Object?>).single!
                  as Map<String, Object?>)['text']!
              as String;
      expect(
        _oracle(
          SpecScenario.timesOut,
          jsonDecode(text) as Map<String, Object?>,
        ),
        isNotEmpty,
      );
    },
  );
}
