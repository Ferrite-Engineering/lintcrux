// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/baseline_violation.dart';
import 'package:lintcrux/domain/models/lint_baseline.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/baseline/baseline_filter.dart';

Violation _v({
  required String ruleId,
  required String file,
  required int line,
  required String message,
  Severity severity = Severity.warning,
}) => Violation(
  engineId: 'verilator',
  ruleId: ruleId,
  severity: severity,
  message: message,
  location: SourceLocation(file: file, line: line, column: 1),
);

void main() {
  group('BaselineFilter.classify', () {
    test('null baseline → every current violation is reported as new', () {
      final current = [
        _v(ruleId: 'r/x', file: '/f.sv', line: 1, message: 'a'),
        _v(ruleId: 'r/y', file: '/f.sv', line: 2, message: 'b'),
      ];
      final delta = BaselineFilter.classify(
        current: current,
        baseline: null,
        projectRoot: '/p',
      );
      expect(delta.newViolations, equals(current));
      expect(delta.persistingViolations, isEmpty);
      expect(delta.resolvedViolations, isEmpty);
      expect(delta.hasNewViolations, isTrue);
    });

    test('empty current run against a populated baseline reports resolved', () {
      const frozen = BaselineViolation(
        fingerprint: 'fp1',
        ruleId: 'r/x',
        filePath: '/f.sv',
        line: 1,
        message: 'a',
      );
      final baseline = LintBaseline(
        baselineId: 'b-1',
        createdAt: DateTime.utc(2026, 5, 25),
        projectPath: '/p',
        frozenViolations: const [frozen],
      );
      final delta = BaselineFilter.classify(
        current: const <Violation>[],
        baseline: baseline,
        projectRoot: '/p',
      );
      expect(delta.newViolations, isEmpty);
      expect(delta.persistingViolations, isEmpty);
      expect(delta.resolvedViolations, equals(const [frozen]));
    });

    test('current run matching baseline fingerprints → persisting only', () {
      final v = _v(ruleId: 'r/x', file: '/f.sv', line: 1, message: 'msg');
      final bv = BaselineViolation.fromViolation(v, projectRoot: '/p');
      final baseline = LintBaseline(
        baselineId: 'b-1',
        createdAt: DateTime.utc(2026, 5, 25),
        projectPath: '/p',
        frozenViolations: [bv],
      );
      final delta = BaselineFilter.classify(
        current: [v],
        baseline: baseline,
        projectRoot: '/p',
      );
      expect(delta.newViolations, isEmpty);
      expect(delta.persistingViolations, equals([v]));
      expect(delta.resolvedViolations, isEmpty);
      expect(delta.hasNewViolations, isFalse);
    });

    test('line-shifted current violation still classified as persisting '
        '(fingerprint stability)', () {
      // The headline property of the baseline workflow: a violation
      // that shifts down by a few lines because surrounding code
      // changed is still "the same" defect.
      final original = _v(
        ruleId: 'verilator/UNUSEDSIGNAL',
        file: '/f.sv',
        line: 42,
        message: 'Signal is not used: foo',
      );
      final shifted = _v(
        ruleId: 'verilator/UNUSEDSIGNAL',
        file: '/f.sv',
        line: 51,
        message: 'Signal is not used: foo',
      );
      final baseline = LintBaseline(
        baselineId: 'b-1',
        createdAt: DateTime.utc(2026, 5, 25),
        projectPath: '/p',
        frozenViolations: [
          BaselineViolation.fromViolation(original, projectRoot: '/p'),
        ],
      );
      final delta = BaselineFilter.classify(
        current: [shifted],
        baseline: baseline,
        projectRoot: '/p',
      );
      expect(delta.persistingViolations, equals([shifted]));
      expect(delta.newViolations, isEmpty);
      expect(delta.resolvedViolations, isEmpty);
    });

    test('mixed scenario: 1 new, 1 persisting, 1 resolved are split into '
        'their respective buckets', () {
      // Baseline holds two violations: a + b.
      final a = _v(ruleId: 'r/A', file: '/f.sv', line: 1, message: 'aa');
      final b = _v(ruleId: 'r/B', file: '/f.sv', line: 2, message: 'bb');
      final baseline = LintBaseline(
        baselineId: 'b-1',
        createdAt: DateTime.utc(2026, 5, 25),
        projectPath: '/p',
        frozenViolations: [
          BaselineViolation.fromViolation(a, projectRoot: '/p'),
          BaselineViolation.fromViolation(b, projectRoot: '/p'),
        ],
      );
      // Current run: a (persists), c (new). b (resolved).
      final c = _v(ruleId: 'r/C', file: '/f.sv', line: 3, message: 'cc');
      final delta = BaselineFilter.classify(
        current: [a, c],
        baseline: baseline,
        projectRoot: '/p',
      );
      expect(delta.persistingViolations, equals([a]));
      expect(delta.newViolations, equals([c]));
      expect(delta.resolvedViolations, hasLength(1));
      expect(delta.resolvedViolations.single.ruleId, 'r/B');
    });

    test('output lists are unmodifiable', () {
      final delta = BaselineFilter.classify(
        current: [
          _v(ruleId: 'r/x', file: '/f.sv', line: 1, message: 'a'),
        ],
        baseline: null,
        projectRoot: '/p',
      );
      expect(
        () => delta.newViolations.add(
          _v(ruleId: 'r/y', file: '/f.sv', line: 2, message: 'b'),
        ),
        throwsUnsupportedError,
      );
    });

    test('resolved violations are emitted in baseline order, not '
        'set-iteration order', () {
      // Baseline holds three violations in the order [A, B, C]. The
      // current run resolves all three (empty current). The
      // `resolvedViolations` list must come out in baseline-declared
      // order so the audit / diff view is deterministic.
      final bvA = BaselineViolation(
        fingerprint: BaselineFingerprint.compute(
          ruleId: 'r/A',
          filePath: '/f.sv',
          message: 'A',
        ),
        ruleId: 'r/A',
        filePath: '/f.sv',
        line: 1,
        message: 'A',
      );
      final bvB = BaselineViolation(
        fingerprint: BaselineFingerprint.compute(
          ruleId: 'r/B',
          filePath: '/f.sv',
          message: 'B',
        ),
        ruleId: 'r/B',
        filePath: '/f.sv',
        line: 2,
        message: 'B',
      );
      final bvC = BaselineViolation(
        fingerprint: BaselineFingerprint.compute(
          ruleId: 'r/C',
          filePath: '/f.sv',
          message: 'C',
        ),
        ruleId: 'r/C',
        filePath: '/f.sv',
        line: 3,
        message: 'C',
      );
      final baseline = LintBaseline(
        baselineId: 'b-1',
        createdAt: DateTime.utc(2026, 5, 25),
        projectPath: '/p',
        frozenViolations: [bvA, bvB, bvC],
      );
      final delta = BaselineFilter.classify(
        current: const <Violation>[],
        baseline: baseline,
        projectRoot: '/p',
      );
      expect(
        delta.resolvedViolations.map((v) => v.ruleId).toList(),
        equals(['r/A', 'r/B', 'r/C']),
      );
    });
    test('a baseline set in one checkout classifies a run in another', () {
      // The CI case: the baseline is recorded at a desktop path and read
      // on a runner checked out somewhere else entirely.
      Violation at(String root) => _v(
        ruleId: 'verilator/UNUSEDSIGNAL',
        file: '$root/rtl/fifo.sv',
        line: 7,
        message: 'Signal is not used: rd_ptr',
      );
      final baseline = LintBaseline(
        baselineId: 'b-1',
        createdAt: DateTime.utc(2026, 5, 25),
        projectPath: '/Users/alice/src/soc',
        frozenViolations: [
          BaselineViolation.fromViolation(
            at('/Users/alice/src/soc'),
            projectRoot: '/Users/alice/src/soc',
          ),
        ],
      );
      final run = at('/home/runner/work/soc/soc');
      final delta = BaselineFilter.classify(
        current: [run],
        baseline: baseline,
        projectRoot: '/home/runner/work/soc/soc',
      );
      expect(delta.persistingViolations, equals([run]));
      expect(delta.newViolations, isEmpty);
    });

    test('a Windows checkout matches a baseline set on macOS', () {
      final baseline = LintBaseline(
        baselineId: 'b-1',
        createdAt: DateTime.utc(2026, 5, 25),
        projectPath: '/Users/alice/src/soc',
        frozenViolations: [
          BaselineViolation.fromViolation(
            _v(
              ruleId: 'r/X',
              file: '/Users/alice/src/soc/rtl/top.sv',
              line: 1,
              message: 'm',
            ),
            projectRoot: '/Users/alice/src/soc',
          ),
        ],
      );
      final run = _v(
        ruleId: 'r/X',
        file: r'D:\a\soc\soc\rtl\top.sv',
        line: 1,
        message: 'm',
      );
      final delta = BaselineFilter.classify(
        current: [run],
        baseline: baseline,
        projectRoot: r'D:\a\soc\soc',
      );
      expect(delta.persistingViolations, equals([run]));
    });

    test('a file at a different path inside the project is new', () {
      final baseline = LintBaseline(
        baselineId: 'b-1',
        createdAt: DateTime.utc(2026, 5, 25),
        projectPath: '/a/proj',
        frozenViolations: [
          BaselineViolation.fromViolation(
            _v(
              ruleId: 'r/X',
              file: '/a/proj/rtl/top.sv',
              line: 1,
              message: 'm',
            ),
            projectRoot: '/a/proj',
          ),
        ],
      );
      final moved = _v(
        ruleId: 'r/X',
        file: '/b/proj/ip/top.sv',
        line: 1,
        message: 'm',
      );
      final delta = BaselineFilter.classify(
        current: [moved],
        baseline: baseline,
        projectRoot: '/b/proj',
      );
      expect(delta.newViolations, equals([moved]));
    });
  });
}
