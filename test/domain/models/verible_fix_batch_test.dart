// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/verible_fix_confidence.dart';
import 'package:lintcrux/domain/models/verible_fix_batch.dart';
import 'package:lintcrux/domain/models/verible_fix_proposal.dart';

VeribleFixProposal _p(String id, VeribleFixConfidence c) => VeribleFixProposal(
  id: id,
  filePath: '/a.sv',
  lineRangeBegin: 1,
  lineRangeEnd: 1,
  originalText: 'x',
  replacementText: 'y',
  description: 'd',
  ruleId: 'r',
  confidence: c,
);

void main() {
  group('VeribleFixBatch', () {
    test('round-trips through JSON', () {
      final original = VeribleFixBatch(
        batchId: 'b1',
        generatedAt: DateTime.utc(2026, 5, 25),
        sourceProject: '/proj',
        proposals: [
          _p('p1', VeribleFixConfidence.high),
          _p('p2', VeribleFixConfidence.medium),
        ],
      );
      final json = original.toJson();
      final parsed = VeribleFixBatch.fromJson(json);
      expect(parsed, equals(original));
    });

    test('confidenceCounts buckets correctly', () {
      final batch = VeribleFixBatch(
        batchId: 'b1',
        generatedAt: DateTime.utc(2026),
        sourceProject: '/p',
        proposals: [
          _p('p1', VeribleFixConfidence.high),
          _p('p2', VeribleFixConfidence.high),
          _p('p3', VeribleFixConfidence.medium),
        ],
      );
      expect(batch.confidenceCounts['high'], 2);
      expect(batch.confidenceCounts['medium'], 1);
      expect(batch.confidenceCounts['low'], isNull);
    });

    test('copyWith preserves untouched fields', () {
      final batch = VeribleFixBatch(
        batchId: 'b1',
        generatedAt: DateTime.utc(2026),
        sourceProject: '/p',
        proposals: [_p('p1', VeribleFixConfidence.high)],
      );
      final updated = batch.copyWith(dryRunOnly: false);
      expect(updated.dryRunOnly, isFalse);
      expect(updated.batchId, 'b1');
      expect(updated.proposals, hasLength(1));
    });

    test('fromJson rejects missing batchId', () {
      expect(
        () => VeribleFixBatch.fromJson(const {}),
        throwsA(isA<FormatException>()),
      );
    });

    test('empty proposal list is valid', () {
      final empty = VeribleFixBatch(
        batchId: 'b1',
        generatedAt: DateTime.utc(2026),
        sourceProject: '/p',
        proposals: const [],
      );
      expect(empty.proposals, isEmpty);
      expect(empty.confidenceCounts, isEmpty);
    });
  });
}
