// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/run.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';

void main() {
  const v = Violation(
    engineId: 'verilator',
    ruleId: 'verilator/UNUSEDSIGNAL',
    severity: Severity.warning,
    message: 'm',
    location: SourceLocation(file: '/x.v', line: 1, column: 1),
  );
  final t0 = DateTime.utc(2026, 5, 22, 10);
  final t1 = DateTime.utc(2026, 5, 22, 10, 0, 5);

  Run make({bool success = true}) => Run(
    id: 'r-1',
    engineId: 'verilator',
    engineVersion: 'verilator 5.026',
    startedAt: t0,
    finishedAt: t1,
    violations: const [v],
    success: success,
  );

  group('Run', () {
    test('duration is finishedAt - startedAt', () {
      expect(make().duration, const Duration(seconds: 5));
    });

    test('defaults — success true, no exitCode or errorMessage', () {
      final r = make();
      expect(r.success, isTrue);
      expect(r.exitCode, isNull);
      expect(r.errorMessage, isNull);
    });

    test('copyWith — mark failure', () {
      final r = make();
      final next = r.copyWith(
        success: false,
        exitCode: 1,
        errorMessage: 'crashed',
      );
      expect(next.success, isFalse);
      expect(next.exitCode, 1);
      expect(next.errorMessage, 'crashed');
      expect(next.violations, r.violations);
    });

    test('== treats matching content as equal', () {
      final a = make();
      final b = make();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('== distinguishes failure state', () {
      final a = make();
      final b = make(success: false);
      expect(a, isNot(b));
    });
  });
}
