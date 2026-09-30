// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/baseline_violation.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';

void main() {
  group('BaselineFingerprint', () {
    test('identical inputs produce identical hashes', () {
      final a = BaselineFingerprint.compute(
        ruleId: 'verilator/UNUSEDSIGNAL',
        filePath: '/abs/path/cpu.sv',
        message: 'Signal is not used: foo',
      );
      final b = BaselineFingerprint.compute(
        ruleId: 'verilator/UNUSEDSIGNAL',
        filePath: '/abs/path/cpu.sv',
        message: 'Signal is not used: foo',
      );
      expect(a, equals(b));
      // The fingerprint is a 16-character lowercase hex string.
      expect(a, matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('different ruleId produces different hash', () {
      final a = BaselineFingerprint.compute(
        ruleId: 'verilator/UNUSEDSIGNAL',
        filePath: '/abs/path/cpu.sv',
        message: 'msg',
      );
      final b = BaselineFingerprint.compute(
        ruleId: 'verilator/UNDRIVEN',
        filePath: '/abs/path/cpu.sv',
        message: 'msg',
      );
      expect(a, isNot(equals(b)));
    });

    test('different filePath produces different hash', () {
      final a = BaselineFingerprint.compute(
        ruleId: 'verilator/UNUSEDSIGNAL',
        filePath: '/abs/path/cpu.sv',
        message: 'msg',
      );
      final b = BaselineFingerprint.compute(
        ruleId: 'verilator/UNUSEDSIGNAL',
        filePath: '/abs/path/alu.sv',
        message: 'msg',
      );
      expect(a, isNot(equals(b)));
    });

    test(
      'whitespace normalization in message — trailing whitespace tolerated',
      () {
        // Engines that pretty-print with trailing newlines / spaces
        // should not move the fingerprint between runs. The normalizer
        // collapses runs of whitespace and trims edges.
        final a = BaselineFingerprint.compute(
          ruleId: 'r/x',
          filePath: '/f',
          message: 'Signal is not used: foo',
        );
        final b = BaselineFingerprint.compute(
          ruleId: 'r/x',
          filePath: '/f',
          message: '  Signal is not used: foo  \n',
        );
        expect(a, equals(b));
      },
    );

    test('whitespace normalization in message — collapsed inner whitespace '
        'tolerated', () {
      final a = BaselineFingerprint.compute(
        ruleId: 'r/x',
        filePath: '/f',
        message: 'Signal is not used: foo',
      );
      final b = BaselineFingerprint.compute(
        ruleId: 'r/x',
        filePath: '/f',
        message: 'Signal\tis  not   used:    foo',
      );
      expect(a, equals(b));
    });
  });

  group('BaselineViolation', () {
    test('fromViolation derives all fields from the live Violation', () {
      const v = Violation(
        engineId: 'verilator',
        ruleId: 'verilator/UNUSEDSIGNAL',
        severity: Severity.warning,
        message: 'Signal is not used: foo',
        location: SourceLocation(file: '/abs/cpu.sv', line: 42, column: 1),
      );
      final bv = BaselineViolation.fromViolation(v, projectRoot: '/abs');
      expect(bv.ruleId, 'verilator/UNUSEDSIGNAL');
      expect(bv.filePath, '/abs/cpu.sv');
      expect(bv.line, 42);
      expect(bv.message, 'Signal is not used: foo');
      expect(
        bv.fingerprint,
        BaselineFingerprint.compute(
          ruleId: 'verilator/UNUSEDSIGNAL',
          filePath: 'cpu.sv',
          message: 'Signal is not used: foo',
        ),
        reason: 'the fingerprint hashes the root-relative path',
      );
    });

    test('line shift on the live violation does NOT move the fingerprint', () {
      // The headline property: a violation that shifts down by a few
      // lines because a preceding `import` was added must still count
      // as the same defect against the baseline.
      const original = Violation(
        engineId: 'verilator',
        ruleId: 'verilator/UNUSEDSIGNAL',
        severity: Severity.warning,
        message: 'Signal is not used: foo',
        location: SourceLocation(file: '/abs/cpu.sv', line: 42, column: 1),
      );
      const shifted = Violation(
        engineId: 'verilator',
        ruleId: 'verilator/UNUSEDSIGNAL',
        severity: Severity.warning,
        message: 'Signal is not used: foo',
        location: SourceLocation(file: '/abs/cpu.sv', line: 51, column: 1),
      );
      final bvOriginal = BaselineViolation.fromViolation(
        original,
        projectRoot: '/abs',
      );
      final bvShifted = BaselineViolation.fromViolation(
        shifted,
        projectRoot: '/abs',
      );
      // Same fingerprint — line is not part of the input.
      expect(bvShifted.fingerprint, equals(bvOriginal.fingerprint));
      // But the recorded `line` differs.
      expect(bvOriginal.line, 42);
      expect(bvShifted.line, 51);
    });

    test('toJson / fromJson round-trip preserves every field', () {
      const bv = BaselineViolation(
        fingerprint: 'deadbeefdeadbeef',
        ruleId: 'verilator/UNUSEDSIGNAL',
        filePath: '/abs/cpu.sv',
        line: 42,
        message: 'Signal is not used: foo',
      );
      final round = BaselineViolation.fromJson(bv.toJson());
      expect(round, equals(bv));
    });

    test('fromJson rejects a missing fingerprint', () {
      expect(
        () => BaselineViolation.fromJson(const <String, dynamic>{
          'ruleId': 'r/x',
          'filePath': '/f',
          'line': 1,
          'message': 'm',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson rejects a non-positive line', () {
      expect(
        () => BaselineViolation.fromJson(const <String, dynamic>{
          'fingerprint': 'abc',
          'ruleId': 'r/x',
          'filePath': '/f',
          'line': 0,
          'message': 'm',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('equality is field-based', () {
      const a = BaselineViolation(
        fingerprint: 'fp',
        ruleId: 'r/x',
        filePath: '/f',
        line: 1,
        message: 'm',
      );
      const b = BaselineViolation(
        fingerprint: 'fp',
        ruleId: 'r/x',
        filePath: '/f',
        line: 1,
        message: 'm',
      );
      const c = BaselineViolation(
        fingerprint: 'fp',
        ruleId: 'r/x',
        filePath: '/f',
        line: 2, // different line
        message: 'm',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
  group('BaselineFingerprint.forProject', () {
    String fp(String file, String root, {String message = 'm'}) =>
        BaselineFingerprint.forProject(
          ruleId: 'r/X',
          filePath: file,
          message: message,
          projectRoot: root,
        );

    test('is independent of where the project is checked out', () {
      expect(
        fp('/Users/alice/soc/rtl/a.sv', '/Users/alice/soc'),
        fp('/home/runner/work/soc/soc/rtl/a.sv', '/home/runner/work/soc/soc'),
      );
    });

    test('a trailing separator on the root changes nothing', () {
      expect(fp('/p/rtl/a.sv', '/p/'), fp('/p/rtl/a.sv', '/p'));
    });

    test('a Windows checkout hashes the same relative path', () {
      expect(
        fp(r'C:\work\soc\rtl\a.sv', r'C:\work\soc'),
        fp('/Users/alice/soc/rtl/a.sv', '/Users/alice/soc'),
      );
    });

    test('a file outside the root keeps its path', () {
      expect(
        BaselineFingerprint.projectRelativePath('/ip/fifo.sv', '/p'),
        '/ip/fifo.sv',
      );
      expect(
        BaselineFingerprint.projectRelativePath('<module:top>', '/p'),
        '<module:top>',
      );
    });

    test('the root is stripped from a message that quotes a path', () {
      expect(
        fp(
          '/a/soc/top.sv',
          '/a/soc',
          message: "ERROR: can't open /a/soc/rtl/pkg.sv",
        ),
        fp(
          '/b/soc/top.sv',
          '/b/soc',
          message: "ERROR: can't open /b/soc/rtl/pkg.sv",
        ),
      );
    });

    test('baselineFingerprintFor answers per root, not per instance', () {
      const v = Violation(
        engineId: 'e',
        ruleId: 'r/X',
        severity: Severity.warning,
        message: 'm',
        location: SourceLocation(file: '/p/rtl/a.sv', line: 1, column: 1),
      );
      final inside = baselineFingerprintFor(v, projectRoot: '/p');
      final outside = baselineFingerprintFor(v, projectRoot: '/q');
      expect(inside, fp('/p/rtl/a.sv', '/p'));
      expect(outside, isNot(inside));
      expect(baselineFingerprintFor(v, projectRoot: '/p'), inside);
    });

    test('withProjectFingerprint recomputes a stored absolute entry', () {
      final legacy = BaselineViolation(
        fingerprint: BaselineFingerprint.compute(
          ruleId: 'r/X',
          filePath: '/p/rtl/a.sv',
          message: 'm',
        ),
        ruleId: 'r/X',
        filePath: '/p/rtl/a.sv',
        line: 3,
        message: 'm',
      );
      final migrated = legacy.withProjectFingerprint('/p');
      expect(migrated.fingerprint, fp('/elsewhere/rtl/a.sv', '/elsewhere'));
      expect(migrated.filePath, legacy.filePath);
      expect(migrated.line, 3);
    });
  });
}
