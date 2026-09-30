// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/cli/cli_exit_codes.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/engine_run_status.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/domain/models/waiver.dart';
import 'package:lintcrux/services/headless/headless_reporter.dart';
import 'package:lintcrux/services/headless/headless_run_result.dart';

void main() {
  Violation violation({
    String file = '/repo/rtl/top.sv',
    int line = 12,
    int column = 3,
    Severity severity = Severity.warning,
    String rule = 'verilator/WIDTHTRUNC',
    String message = 'truncation',
    bool suppressed = false,
  }) {
    return Violation(
      engineId: 'verilator',
      ruleId: rule,
      severity: severity,
      message: message,
      location: SourceLocation(file: file, line: line, column: column),
      suppression: suppressed
          ? Waiver(
              id: 'w1',
              ruleId: rule,
              filePath: file,
              reason: 'pragma',
              createdAt: DateTime.utc(2026),
              author: 'test',
            )
          : null,
    );
  }

  const completed = <String, EngineRunStatus>{
    'verilator': EngineRunStatus(
      engineId: 'verilator',
      phase: EngineRunPhase.completed,
    ),
  };

  group('violation listing', () {
    test('uses the file:line:col: severity: [rule] message shape', () {
      const reporter = HeadlessReporter(relativeTo: '/repo');
      final lines = reporter.stdoutLines(
        HeadlessRunResult(
          exitCode: CliExitCode.clean,
          violations: <Violation>[violation()],
          statuses: completed,
        ),
      );
      // `/` on every host, Windows included: CI log scrapers key on this
      // shape, and a team diffs it between runs on different agents. See
      // `portableRelativePath`.
      expect(
        lines.first,
        'rtl/top.sv:12:3: warning: [verilator/WIDTHTRUNC] truncation',
      );
    });

    test('sorts by severity, then file, then line, then column', () {
      const reporter = HeadlessReporter();
      final lines = reporter.stdoutLines(
        HeadlessRunResult(
          exitCode: CliExitCode.clean,
          statuses: completed,
          violations: <Violation>[
            violation(severity: Severity.note, line: 1, message: 'note'),
            violation(severity: Severity.error, line: 99, message: 'error'),
            violation(line: 5, message: 'warn-5'),
            violation(line: 2, message: 'warn-2'),
          ],
        ),
      );
      expect(lines[0], contains('error'));
      expect(lines[1], contains('warn-2'));
      expect(lines[2], contains('warn-5'));
      expect(lines[3], contains('note'));
    });

    test('suppressed violations are not listed and not counted', () {
      const reporter = HeadlessReporter();
      final lines = reporter.stdoutLines(
        HeadlessRunResult(
          exitCode: CliExitCode.clean,
          statuses: completed,
          violations: <Violation>[violation(suppressed: true)],
          suppressedCount: 1,
        ),
      );
      expect(lines.where((l) => l.contains('WIDTHTRUNC')), isEmpty);
      expect(lines.last, contains('no violations'));
      expect(lines.last, contains('1 suppressed'));
    });

    test('--quiet drops the listing but keeps the summary', () {
      const reporter = HeadlessReporter(quiet: true);
      final lines = reporter.stdoutLines(
        HeadlessRunResult(
          exitCode: CliExitCode.violations,
          statuses: completed,
          violations: <Violation>[violation()],
        ),
      );
      expect(lines, hasLength(1));
      expect(lines.single, contains('1 violations'));
    });

    test('new-vs-baseline violations are annotated', () {
      const reporter = HeadlessReporter();
      final v = violation();
      final lines = reporter.stdoutLines(
        HeadlessRunResult(
          exitCode: CliExitCode.newViolations,
          statuses: completed,
          violations: <Violation>[v],
          newViolations: <Violation>[v],
          baselinePath: '/repo/.lintcrux-baseline.json',
          baselineApplied: true,
        ),
      );
      expect(lines.first, endsWith('(new)'));
    });
  });

  group('summary line', () {
    test('names the exit code and its label', () {
      const reporter = HeadlessReporter();
      for (final code in CliExitCode.all) {
        final lines = reporter.stdoutLines(
          HeadlessRunResult(exitCode: code, statuses: completed),
        );
        expect(
          lines.last,
          contains('[exit $code: ${CliExitCode.labelFor(code)}]'),
        );
      }
    });

    test('breaks the count down per severity', () {
      const reporter = HeadlessReporter();
      final lines = reporter.stdoutLines(
        HeadlessRunResult(
          exitCode: CliExitCode.violations,
          statuses: completed,
          projectName: 'design',
          violations: <Violation>[
            violation(severity: Severity.error),
            violation(),
            violation(),
          ],
        ),
      );
      expect(lines.last, contains('design'));
      expect(lines.last, contains('3 violations'));
      expect(lines.last, contains('1 error'));
      expect(lines.last, contains('2 warning'));
    });

    test('reports the baseline breakdown when the gate ran', () {
      const reporter = HeadlessReporter();
      final v = violation();
      final lines = reporter.stdoutLines(
        HeadlessRunResult(
          exitCode: CliExitCode.newViolations,
          statuses: completed,
          violations: <Violation>[v],
          newViolations: <Violation>[v],

          resolvedViolationCount: 4,
          baselinePath: '/repo/.lintcrux-baseline.json',
          baselineApplied: true,
        ),
      );
      expect(lines.last, contains('1 new'));
      expect(lines.last, contains('0 pre-existing'));
      expect(lines.last, contains('4 resolved'));
    });

    test('says so when the baseline was requested but absent', () {
      const reporter = HeadlessReporter();
      final lines = reporter.stdoutLines(
        const HeadlessRunResult(
          exitCode: CliExitCode.clean,
          statuses: completed,
          baselinePath: '/repo/.lintcrux-baseline.json',
        ),
      );
      expect(lines.last, contains('no baseline found'));
    });
  });

  group('stderr and the pre-engine failure path', () {
    test('diagnostics precede errors and are prefixed distinctly', () {
      const reporter = HeadlessReporter();
      final lines = reporter.stderrLines(
        const HeadlessRunResult(
          exitCode: CliExitCode.runFailed,
          diagnostics: <String>['engine "ghdl" skipped'],
          problems: <String>['engine "verilator" failed'],
        ),
      );
      expect(lines, <String>[
        'lintcrux: note: engine "ghdl" skipped',
        'lintcrux: error: engine "verilator" failed',
      ]);
    });

    test('a run that never reached the engines prints no summary', () {
      // Otherwise a usage error prints `no violations` on stdout under
      // the error, which reads as a clean result.
      const reporter = HeadlessReporter();
      final lines = reporter.stdoutLines(
        const HeadlessRunResult(
          exitCode: CliExitCode.usage,
          problems: <String>['"notes.txt" is not a project file'],
        ),
      );
      expect(lines, isEmpty);
    });

    test('a run that DID reach the engines still summarizes on failure', () {
      const reporter = HeadlessReporter();
      final lines = reporter.stdoutLines(
        const HeadlessRunResult(
          exitCode: CliExitCode.runFailed,
          statuses: completed,
          problems: <String>['engine "verible" is unavailable'],
        ),
      );
      expect(lines.single, contains('run-failed'));
    });
  });
}
