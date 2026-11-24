// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The pieces of the `--json` documents the goldens do not reach: the
// classifier's gate and fallback branches, the CDC withholding, the
// Verilator configuration reader, and the command-line flags.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_mcp/crux_mcp.dart' hide HeadlessTelemetry;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/cli/cli_args_parser.dart';
import 'package:lintcrux/core/cli/cli_exit_codes.dart';
import 'package:lintcrux/core/cli/lintcrux_cli.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/engine_run_status.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/headless/lint_document.dart';
import 'package:lintcrux/headless/waivers_command.dart';
import 'package:lintcrux/services/headless/headless_run_result.dart';
import 'package:path/path.dart' as p;

import 'support/spec_engines.dart';

Violation _finding(Severity severity) => Violation(
  engineId: 'verilator',
  ruleId: 'verilator/WIDTH',
  severity: severity,
  message: 'a finding',
  location: const SourceLocation(file: '/r/a.sv', line: 1, column: 1),
);

void main() {
  group('classifyLintRun', () {
    const ran = <String, EngineRunStatus>{
      'verilator': EngineRunStatus(
        engineId: 'verilator',
        phase: EngineRunPhase.completed,
      ),
    };

    test(
      'each of LintCrux gates is failed_gate, with the gate as the error',
      () {
        for (final (code, gate) in <(int, String)>[
          (CliExitCode.violations, 'gate.findings'),
          (CliExitCode.newViolations, 'gate.new_findings'),
          (CliExitCode.overThreshold, 'gate.threshold'),
        ]) {
          final c = classifyLintRun(
            HeadlessRunResult(
              exitCode: code,
              statuses: ran,
              violations: <Violation>[_finding(Severity.error)],
              newViolations: <Violation>[_finding(Severity.error)],
            ),
          );
          expect(c.outcome, McpOutcome.failedGate);
          expect(c.errors.single.code, gate);
        }
      },
    );

    test('an unclassified problem is never an answer', () {
      for (final (code, outcome) in <(int, McpOutcome)>[
        (CliExitCode.runFailed, McpOutcome.engineError),
        (CliExitCode.usage, McpOutcome.usageError),
        (CliExitCode.dataError, McpOutcome.inputError),
        (CliExitCode.clean, McpOutcome.engineError),
      ]) {
        final c = classifyLintRun(
          HeadlessRunResult(exitCode: code, problems: const <String>['why']),
        );
        expect(c.outcome, outcome, reason: '$code');
        expect(c.errors.single.message, 'why');
      }
      final silent = classifyLintRun(const HeadlessRunResult(exitCode: 3));
      expect(silent.outcome, McpOutcome.engineError);
    });

    test('an engine failure outranks an input problem', () {
      final c = classifyLintRun(
        const HeadlessRunResult(
          exitCode: CliExitCode.runFailed,
          failures: <HeadlessFailure>[
            HeadlessFailure(HeadlessFailureKind.input, 'input.baseline', 'b'),
            HeadlessFailure(HeadlessFailureKind.engine, 'engine.failed', 'e'),
          ],
        ),
      );
      expect(c.outcome, McpOutcome.engineError);
      expect(c.errors.map((e) => e.code), <String>[
        'input.baseline',
        'engine.failed',
      ]);
    });
  });

  group('openCoreWithheld', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('lintcrux_wh_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    LintProject project() => LintProject(
      name: 'x',
      rootPath: tmp.path,
      sourceFiles: <String>[p.join(tmp.path, 'rtl', 'a.sv')],
    );

    test('says nothing when nothing is withheld', () {
      expect(openCoreWithheld(project(), cdcRan: true), isEmpty);
    });

    test('a cdc.yaml beside the sources is withheld only when CDC ran', () {
      File(p.join(tmp.path, 'rtl', 'cdc.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('clocks: []\n');
      expect(openCoreWithheld(project(), cdcRan: false), isEmpty);
      final d = openCoreWithheld(project(), cdcRan: true).single;
      expect(d.code, kMcpWithheldCode);
      expect(d.severity, McpSeverity.warning);
      expect(d.message, contains('cdc.yaml'));
    });
  });

  group('parseVltLintOff', () {
    test('reads the rule and keeps the directive without its comment', () {
      final d = parseVltLintOff(
        '  lint_off -rule WIDTH -file "*/a.sv" -lines 3-4 // why',
      )!;
      expect(d.rule, 'verilator/WIDTH');
      expect(d.text, 'lint_off -rule WIDTH -file "*/a.sv" -lines 3-4');
      expect(parseVltLintOff('lint_off -msg UNUSED')!.rule, 'verilator/UNUSED');
      expect(parseVltLintOff('lint_off -file "*"')!.rule, 'verilator/*');
    });

    test('anything else is not a waiver', () {
      for (final line in <String>[
        '`verilator_config',
        '// lint_off -rule WIDTH',
        'lint_on -rule WIDTH',
        'tracing_off -file "*"',
        '',
      ]) {
        expect(parseVltLintOff(line), isNull, reason: line);
      }
    });
  });

  group('the command line', () {
    test(
      '--json, --limit and --offset parse, and refuse what they cannot do',
      () {
        final parser = CliArgsParser();
        final ok = parser.parse(<String>[
          'p.lintcrux',
          '--json',
          '--limit',
          '0',
          '--offset',
          '7',
        ]);
        expect(ok.args!.json, isTrue);
        expect(ok.args!.limit, 0);
        expect(ok.args!.offset, 7);
        for (final args in <List<String>>[
          <String>['p.lintcrux', '--limit', '5'],
          <String>['p.lintcrux', '--json', '--limit', '1001'],
          <String>['p.lintcrux', '--json', '--offset', '-1'],
          <String>['p.lintcrux', '--json', '--limit', 'ten'],
          <String>['p.lintcrux', '--json', '--sarif', 'out.sarif'],
          <String>['p.lintcrux', '--json', '--export', 'csv', '--out', 'x'],
        ]) {
          expect(parser.parse(args).isSuccess, isFalse, reason: '$args');
        }
      },
    );

    test(
      'a bad command line with --json still writes a usage document',
      () async {
        final out = <String>[];
        final code =
            await LintcruxCli(
              registry: specRegistry(SpecScenario.ok),
              installSignalReaper: false,
              mcpTelemetry: () => null,
            ).run(
              <String>['--json', '--no-such-flag'],
              stdoutSink: out.add,
              stderrSink: (_) {},
            );
        expect(code, CliExitCode.usage);
        final doc = jsonDecode(out.single) as Map<String, Object?>;
        expect(doc['outcome'], 'usage_error');
        expect(doc['command'], 'lint');
      },
    );

    test('rule and waivers print a plain form without --json', () async {
      final out = <String>[];
      final cli = LintcruxCli(
        installSignalReaper: false,
        mcpTelemetry: () => null,
      );
      expect(
        await cli.run(
          <String>['rule', 'verilator/WIDTH'],
          stdoutSink: out.add,
          stderrSink: (_) {},
        ),
        0,
      );
      expect(out.first, 'verilator/WIDTH');
      out.clear();
      expect(
        await cli.run(
          <String>[
            'waivers',
            p.join('spec', 'fixtures', 'design', 'design.lintcrux'),
          ],
          stdoutSink: out.add,
          stderrSink: (_) {},
        ),
        0,
      );
      // The committed fixture has no baseline (spec/mcp/runtime/ holds it):
      // the pragma and the two lint_off lines.
      expect(out.last, '3 waivers');
      expect(
        await cli.run(<String>['rule'], stdoutSink: (_) {}, stderrSink: (_) {}),
        64,
      );
      expect(
        await cli.run(
          <String>['rule', '--help'],
          stdoutSink: (_) {},
          stderrSink: (_) {},
        ),
        0,
      );
    });
  });
}
