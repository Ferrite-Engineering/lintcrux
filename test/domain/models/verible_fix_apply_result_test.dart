// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/verible_fix_apply_result.dart';

void main() {
  group('VeribleFixApplyResult', () {
    test('equality is structural', () {
      const a = VeribleFixApplyResult(
        proposalId: 'p1',
        outcome: VeribleFixApplyOutcome.applied,
      );
      const b = VeribleFixApplyResult(
        proposalId: 'p1',
        outcome: VeribleFixApplyOutcome.applied,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('failure carries errorMessage', () {
      const r = VeribleFixApplyResult(
        proposalId: 'p1',
        outcome: VeribleFixApplyOutcome.failed,
        errorMessage: 'permission denied',
      );
      expect(r.outcome, VeribleFixApplyOutcome.failed);
      expect(r.errorMessage, 'permission denied');
    });

    test('conflict carries conflictingProposalId', () {
      const r = VeribleFixApplyResult(
        proposalId: 'p1',
        outcome: VeribleFixApplyOutcome.conflictedWithOtherFix,
        conflictingProposalId: 'p2',
      );
      expect(r.outcome, VeribleFixApplyOutcome.conflictedWithOtherFix);
      expect(r.conflictingProposalId, 'p2');
    });

    test('toString surfaces the outcome', () {
      const r = VeribleFixApplyResult(
        proposalId: 'p1',
        outcome: VeribleFixApplyOutcome.skippedByUser,
      );
      expect(r.toString(), contains('p1'));
      expect(r.toString(), contains('skippedByUser'));
    });
  });
}
