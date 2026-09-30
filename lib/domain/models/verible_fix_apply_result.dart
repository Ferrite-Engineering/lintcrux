// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Outcome categories for one [VeribleFixProposal] dispatched through
/// the apply path.
enum VeribleFixApplyOutcome {
  /// The proposal's text replacement was written to the file
  /// successfully.
  applied,

  /// The user did not include this proposal in the apply batch (e.g.
  /// the checkbox in `FixReviewDialog` was unchecked). The proposal
  /// was preserved in the batch's audit trail but never written.
  skippedByUser,

  /// The proposal targeted lines that overlapped another higher-
  /// confidence proposal selected in the same apply batch. The
  /// conflict-resolution logic preserves the higher-confidence fix
  /// and emits a `conflictedWithOtherFix` result for the displaced
  /// proposal.
  conflictedWithOtherFix,

  /// The apply path attempted the write but a filesystem-level error
  /// (permission, disk full, file disappeared, encoding mismatch)
  /// prevented it. The `errorMessage` field carries the diagnostic.
  failed,
}

/// One per-proposal outcome from a single
/// [VeribleFixService.apply] invocation.
@immutable
class VeribleFixApplyResult {
  /// Creates a [VeribleFixApplyResult].
  const VeribleFixApplyResult({
    required this.proposalId,
    required this.outcome,
    this.errorMessage,
    this.conflictingProposalId,
  });

  /// The [VeribleFixProposal.id] this result corresponds to.
  final String proposalId;

  /// Outcome bucket.
  final VeribleFixApplyOutcome outcome;

  /// Diagnostic text when [outcome] is `failed`; null otherwise.
  /// Surfaced verbatim in the apply summary dialog.
  final String? errorMessage;

  /// When [outcome] is `conflictedWithOtherFix`, the id of the
  /// higher-confidence proposal that displaced this one. Surfaced in
  /// the summary so the user can audit the resolution.
  final String? conflictingProposalId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VeribleFixApplyResult &&
        other.proposalId == proposalId &&
        other.outcome == outcome &&
        other.errorMessage == errorMessage &&
        other.conflictingProposalId == conflictingProposalId;
  }

  @override
  int get hashCode => Object.hash(
    proposalId,
    outcome,
    errorMessage,
    conflictingProposalId,
  );

  @override
  String toString() =>
      'VeribleFixApplyResult($proposalId, ${outcome.name}'
      '${errorMessage != null ? ', err=$errorMessage' : ''}'
      '${conflictingProposalId != null ? ', conflict=$conflictingProposalId' : ''}'
      ')';
}
