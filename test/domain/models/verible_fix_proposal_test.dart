// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/verible_fix_confidence.dart';
import 'package:lintcrux/domain/models/verible_fix_proposal.dart';

void main() {
  group('VeribleFixProposal', () {
    test('round-trips through JSON', () {
      const original = VeribleFixProposal(
        id: 'fp-1',
        filePath: '/a.sv',
        lineRangeBegin: 12,
        lineRangeEnd: 14,
        originalText: 'logic foo = 1;',
        replacementText: "logic foo = 1'b1;",
        description: 'use sized literal',
        ruleId: 'verible/literal-sized',
        confidence: VeribleFixConfidence.high,
      );
      final json = original.toJson();
      final parsed = VeribleFixProposal.fromJson(json);
      expect(parsed, equals(original));
    });

    test('fromJson rejects missing required fields', () {
      expect(
        () => VeribleFixProposal.fromJson(const {}),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson rejects unknown confidence enum value', () {
      const json = {
        'id': 'fp-1',
        'filePath': '/a.sv',
        'lineRangeBegin': 1,
        'lineRangeEnd': 1,
        'originalText': 'x',
        'replacementText': 'y',
        'description': 'd',
        'ruleId': 'r',
        'confidence': 'extreme',
      };
      expect(
        () => VeribleFixProposal.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('asserts line range invariants', () {
      expect(
        () => VeribleFixProposal(
          id: 'a',
          filePath: '/a',
          lineRangeBegin: 0,
          lineRangeEnd: 1,
          originalText: 'x',
          replacementText: 'y',
          description: 'd',
          ruleId: 'r',
          confidence: VeribleFixConfidence.high,
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => VeribleFixProposal(
          id: 'a',
          filePath: '/a',
          lineRangeBegin: 5,
          lineRangeEnd: 4,
          originalText: 'x',
          replacementText: 'y',
          description: 'd',
          ruleId: 'r',
          confidence: VeribleFixConfidence.high,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('equality is structural', () {
      const a = VeribleFixProposal(
        id: 'a',
        filePath: '/a',
        lineRangeBegin: 1,
        lineRangeEnd: 1,
        originalText: 'x',
        replacementText: 'y',
        description: 'd',
        ruleId: 'r',
        confidence: VeribleFixConfidence.high,
      );
      const b = VeribleFixProposal(
        id: 'a',
        filePath: '/a',
        lineRangeBegin: 1,
        lineRangeEnd: 1,
        originalText: 'x',
        replacementText: 'y',
        description: 'd',
        ruleId: 'r',
        confidence: VeribleFixConfidence.high,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });
}
