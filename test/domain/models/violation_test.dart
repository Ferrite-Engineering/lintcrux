// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/domain/models/waiver.dart';

void main() {
  const loc = SourceLocation(file: '/tmp/x.v', line: 10, column: 1);

  Violation make({Waiver? suppression}) => Violation(
    engineId: 'verilator',
    ruleId: 'verilator/UNUSEDSIGNAL',
    severity: Severity.warning,
    message: 'signal unused',
    location: loc,
    suppression: suppression,
  );

  group('Violation', () {
    test('isSuppressed reflects suppression presence', () {
      expect(make().isSuppressed, isFalse);
      final waiver = Waiver(
        id: 'w-1',
        ruleId: 'verilator/UNUSEDSIGNAL',
        filePath: '/tmp/x.v',
        reason: 'r',
        author: 'a',
        createdAt: DateTime.utc(2026, 5, 22),
      );
      expect(make(suppression: waiver).isSuppressed, isTrue);
    });

    test('copyWith respects clearSuppression sentinel', () {
      final waiver = Waiver(
        id: 'w-1',
        ruleId: 'verilator/UNUSEDSIGNAL',
        filePath: '/tmp/x.v',
        reason: 'r',
        author: 'a',
        createdAt: DateTime.utc(2026, 5, 22),
      );
      final suppressed = make(suppression: waiver);
      final cleared = suppressed.copyWith(clearSuppression: true);
      expect(cleared.suppression, isNull);
      expect(cleared.isSuppressed, isFalse);
    });

    test('copyWith — leaving suppression null preserves existing waiver', () {
      final waiver = Waiver(
        id: 'w-1',
        ruleId: 'verilator/UNUSEDSIGNAL',
        filePath: '/tmp/x.v',
        reason: 'r',
        author: 'a',
        createdAt: DateTime.utc(2026, 5, 22),
      );
      final v = make(suppression: waiver);
      final next = v.copyWith(message: 'updated message');
      expect(next.suppression, waiver);
      expect(next.message, 'updated message');
    });

    test('== ignores the `raw` SARIF blob', () {
      const a = Violation(
        engineId: 'verilator',
        ruleId: 'verilator/UNUSEDSIGNAL',
        severity: Severity.warning,
        message: 'm',
        location: loc,
        raw: {'foo': 1},
      );
      const b = Violation(
        engineId: 'verilator',
        ruleId: 'verilator/UNUSEDSIGNAL',
        severity: Severity.warning,
        message: 'm',
        location: loc,
        raw: {'bar': 2},
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('== distinguishes differing relatedLocations order', () {
      const a = Violation(
        engineId: 'verilator',
        ruleId: 'verilator/UNUSEDSIGNAL',
        severity: Severity.warning,
        message: 'm',
        location: loc,
        relatedLocations: [
          SourceLocation(file: '/tmp/a.v', line: 1, column: 1),
          SourceLocation(file: '/tmp/b.v', line: 2, column: 1),
        ],
      );
      const b = Violation(
        engineId: 'verilator',
        ruleId: 'verilator/UNUSEDSIGNAL',
        severity: Severity.warning,
        message: 'm',
        location: loc,
        relatedLocations: [
          SourceLocation(file: '/tmp/b.v', line: 2, column: 1),
          SourceLocation(file: '/tmp/a.v', line: 1, column: 1),
        ],
      );
      expect(a, isNot(b));
    });
  });
}
