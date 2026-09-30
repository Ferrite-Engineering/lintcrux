// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/baseline_violation.dart';
import 'package:lintcrux/domain/models/lint_baseline.dart';

void main() {
  group('LintBaseline', () {
    const bv1 = BaselineViolation(
      fingerprint: 'fp1',
      ruleId: 'verilator/UNUSEDSIGNAL',
      filePath: '/abs/cpu.sv',
      line: 42,
      message: 'msg 1',
    );
    const bv2 = BaselineViolation(
      fingerprint: 'fp2',
      ruleId: 'verilator/UNDRIVEN',
      filePath: '/abs/alu.sv',
      line: 7,
      message: 'msg 2',
    );

    test('constructor sets defaults; frozenCount mirrors list length', () {
      final b = LintBaseline(
        baselineId: 'b-1',
        createdAt: DateTime.utc(2026, 5, 25, 12),
        projectPath: '/abs/project',
        frozenViolations: const [bv1, bv2],
      );
      expect(b.version, LintBaseline.currentVersion);
      expect(b.createdBy, isNull);
      expect(b.frozenCount, 2);
    });

    test('fingerprintSet collects all fingerprints', () {
      final b = LintBaseline(
        baselineId: 'b-1',
        createdAt: DateTime.utc(2026, 5, 25),
        projectPath: '/p',
        frozenViolations: const [bv1, bv2],
      );
      expect(b.fingerprintSet, equals({'fp1', 'fp2'}));
    });

    test('copyWith replaces only the named fields', () {
      final b = LintBaseline(
        baselineId: 'b-1',
        createdAt: DateTime.utc(2026, 5, 25),
        projectPath: '/p',
        frozenViolations: const [bv1],
        createdBy: 'mfink',
      );
      final c = b.copyWith(baselineId: 'b-2');
      expect(c.baselineId, 'b-2');
      expect(c.createdBy, 'mfink');
      expect(c.frozenViolations, equals(const [bv1]));
    });

    test('copyWith with clearCreatedBy removes the author tag', () {
      final b = LintBaseline(
        baselineId: 'b-1',
        createdAt: DateTime.utc(2026, 5, 25),
        projectPath: '/p',
        frozenViolations: const [bv1],
        createdBy: 'mfink',
      );
      final c = b.copyWith(clearCreatedBy: true);
      expect(c.createdBy, isNull);
    });

    test('toJson / fromJson round-trip preserves all fields', () {
      final b = LintBaseline(
        baselineId: 'b-1',
        createdAt: DateTime.utc(2026, 5, 25, 12, 30),
        projectPath: '/abs/project',
        frozenViolations: const [bv1, bv2],
        createdBy: 'mfink',
      );
      final round = LintBaseline.fromJson(b.toJson());
      expect(round, equals(b));
    });

    test(
      'round-trip without createdBy omits the field cleanly',
      () {
        final b = LintBaseline(
          baselineId: 'b-1',
          createdAt: DateTime.utc(2026, 5, 25),
          projectPath: '/abs/project',
          frozenViolations: const [bv1],
        );
        final json = b.toJson();
        expect(json.containsKey('createdBy'), isFalse);
        final round = LintBaseline.fromJson(json);
        expect(round.createdBy, isNull);
      },
    );

    test('fromJson rejects an unsupported schema version', () {
      expect(
        () => LintBaseline.fromJson(const <String, dynamic>{
          'version': 99,
          'baselineId': 'b-1',
          'createdAt': '2026-05-25T00:00:00Z',
          'projectPath': '/p',
          'frozenViolations': <Map<String, dynamic>>[],
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('schema version: 99'),
          ),
        ),
      );
    });

    group('version 1 migration', () {
      Map<String, dynamic> v1({String projectPath = '/Users/alice/soc'}) =>
          <String, dynamic>{
            'version': 1,
            'baselineId': 'legacy',
            'createdAt': '2026-05-25T00:00:00Z',
            'projectPath': projectPath,
            'frozenViolations': <Map<String, dynamic>>[
              <String, dynamic>{
                'fingerprint': BaselineFingerprint.compute(
                  ruleId: 'verilator/UNUSEDSIGNAL',
                  filePath: '/Users/alice/soc/rtl/cpu.sv',
                  message: 'msg 1',
                ),
                'ruleId': 'verilator/UNUSEDSIGNAL',
                'filePath': '/Users/alice/soc/rtl/cpu.sv',
                'line': 42,
                'message': 'msg 1',
              },
            ],
          };

      test('recomputes every fingerprint against projectPath', () {
        final b = LintBaseline.fromJson(v1());
        expect(b.version, LintBaseline.currentVersion);
        expect(
          b.frozenViolations.single.fingerprint,
          BaselineFingerprint.forProject(
            ruleId: 'verilator/UNUSEDSIGNAL',
            filePath: '/home/runner/work/soc/soc/rtl/cpu.sv',
            message: 'msg 1',
            projectRoot: '/home/runner/work/soc/soc',
          ),
        );
      });

      test('keeps every other field', () {
        final entry = LintBaseline.fromJson(v1()).frozenViolations.single;
        expect(entry.filePath, '/Users/alice/soc/rtl/cpu.sv');
        expect(entry.line, 42);
        expect(entry.message, 'msg 1');
      });

      test('writes back as the current version', () {
        final json = LintBaseline.fromJson(v1()).toJson();
        expect(json['version'], LintBaseline.currentVersion);
        expect(LintBaseline.fromJson(json), LintBaseline.fromJson(v1()));
      });
    });

    test('fromJson rejects a missing baselineId', () {
      expect(
        () => LintBaseline.fromJson(const <String, dynamic>{
          'version': 1,
          'createdAt': '2026-05-25T00:00:00Z',
          'projectPath': '/p',
          'frozenViolations': <Map<String, dynamic>>[],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('equality is field-based', () {
      final a = LintBaseline(
        baselineId: 'b-1',
        createdAt: DateTime.utc(2026, 5, 25),
        projectPath: '/p',
        frozenViolations: const [bv1, bv2],
      );
      final b = LintBaseline(
        baselineId: 'b-1',
        createdAt: DateTime.utc(2026, 5, 25),
        projectPath: '/p',
        frozenViolations: const [bv1, bv2],
      );
      final c = a.copyWith(baselineId: 'different');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}
