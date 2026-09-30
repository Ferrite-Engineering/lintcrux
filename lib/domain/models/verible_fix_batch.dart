// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/models/verible_fix_proposal.dart';
import 'package:meta/meta.dart';

/// A batch of [VeribleFixProposal]s produced by one
/// [VeribleFixService.dryRun] invocation.
///
/// Batches are the unit of review: the user opens the
/// `FixReviewDialog` against a batch, selects a subset of proposals,
/// and dispatches the apply through the Pro service. The
/// [dryRunOnly] flag transitions from `true` to `false` after apply
/// so the UI can disambiguate "still reviewing" from "already
/// applied" when the batch is re-rendered (e.g. apply-summary view).
@immutable
class VeribleFixBatch {
  /// Creates a [VeribleFixBatch].
  const VeribleFixBatch({
    required this.batchId,
    required this.generatedAt,
    required this.proposals,
    required this.sourceProject,
    this.dryRunOnly = true,
  });

  /// Parses [json] into a [VeribleFixBatch]. Throws [FormatException]
  /// on missing or wrong-typed fields.
  factory VeribleFixBatch.fromJson(Map<String, dynamic> json) {
    final batchId = json['batchId'];
    if (batchId is! String || batchId.isEmpty) {
      throw const FormatException(
        "VeribleFixBatch missing required 'batchId'",
      );
    }
    final generatedAtRaw = json['generatedAt'];
    if (generatedAtRaw is! String) {
      throw const FormatException(
        "VeribleFixBatch missing required 'generatedAt'",
      );
    }
    final sourceProject = json['sourceProject'];
    if (sourceProject is! String) {
      throw const FormatException(
        "VeribleFixBatch missing required 'sourceProject'",
      );
    }
    final dryRunOnly = json['dryRunOnly'];
    final proposalsRaw = json['proposals'];
    if (proposalsRaw is! List) {
      throw const FormatException(
        "VeribleFixBatch 'proposals' must be a list",
      );
    }
    return VeribleFixBatch(
      batchId: batchId,
      generatedAt: DateTime.parse(generatedAtRaw),
      sourceProject: sourceProject,
      dryRunOnly: dryRunOnly is! bool || dryRunOnly,
      proposals: <VeribleFixProposal>[
        for (final entry in proposalsRaw)
          if (entry is Map<String, dynamic>) VeribleFixProposal.fromJson(entry),
      ],
    );
  }

  /// Stable UUID identifying this batch. Survives across the dry-run
  /// → review → apply lifecycle so the apply-summary dialog can refer
  /// back to the originating batch.
  final String batchId;

  /// Timestamp (UTC) when the dry-run produced this batch.
  final DateTime generatedAt;

  /// Ordered list of [VeribleFixProposal]s. Order is determined by
  /// Verible's output (typically file-first, line-second); the UI
  /// surfaces a sort selector to override.
  final List<VeribleFixProposal> proposals;

  /// Absolute path of the project the batch was generated for.
  /// Preserved so the apply path can confirm it's still operating
  /// against the same project root.
  final String sourceProject;

  /// `true` while the batch is in review (no fixes applied yet);
  /// `false` after the apply path runs (regardless of partial
  /// failures). Lets the UI re-render the same batch object as the
  /// apply summary.
  final bool dryRunOnly;

  /// Count of proposals at each confidence level. Used by the review
  /// dialog's summary header.
  Map<String, int> get confidenceCounts {
    final counts = <String, int>{};
    for (final p in proposals) {
      counts[p.confidence.name] = (counts[p.confidence.name] ?? 0) + 1;
    }
    return counts;
  }

  /// Returns a copy with overridden fields.
  VeribleFixBatch copyWith({
    String? batchId,
    DateTime? generatedAt,
    List<VeribleFixProposal>? proposals,
    String? sourceProject,
    bool? dryRunOnly,
  }) {
    return VeribleFixBatch(
      batchId: batchId ?? this.batchId,
      generatedAt: generatedAt ?? this.generatedAt,
      proposals: proposals ?? this.proposals,
      sourceProject: sourceProject ?? this.sourceProject,
      dryRunOnly: dryRunOnly ?? this.dryRunOnly,
    );
  }

  /// Round-trippable JSON view. Key order is deterministic.
  Map<String, Object?> toJson() => <String, Object?>{
    'batchId': batchId,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'sourceProject': sourceProject,
    'dryRunOnly': dryRunOnly,
    'proposals': <Map<String, Object?>>[
      for (final p in proposals) p.toJson(),
    ],
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! VeribleFixBatch) return false;
    if (other.batchId != batchId) return false;
    if (other.generatedAt != generatedAt) return false;
    if (other.sourceProject != sourceProject) return false;
    if (other.dryRunOnly != dryRunOnly) return false;
    if (other.proposals.length != proposals.length) return false;
    for (var i = 0; i < proposals.length; i++) {
      if (other.proposals[i] != proposals[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    batchId,
    generatedAt,
    sourceProject,
    dryRunOnly,
    Object.hashAll(proposals),
  );

  @override
  String toString() =>
      'VeribleFixBatch($batchId, n=${proposals.length}, '
      'dryRunOnly=$dryRunOnly)';
}
