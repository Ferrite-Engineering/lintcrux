// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:meta/meta.dart';

/// Aggregation key for [ViolationTrendStore.queryAggregates].
///
/// Controls what `keyId` semantically means:
///
/// * [perRule] — `keyId` is the rule id; one aggregate per rule per
///   bucket.
/// * [perSeverity] — `keyId` is the severity name; one aggregate per
///   severity per bucket. Drives the severity-drift chart's stack.
/// * [perFile] — `keyId` is the file path; one aggregate per file
///   per bucket. Used by the calendar heatmap when scoped to a file.
/// * [global] — `keyId` is `null`; one aggregate per bucket covering
///   every violation regardless of rule/severity/file. Drives the
///   project trend chart.
enum ViolationTrendAggregateKey {
  /// One aggregate per rule per time bucket.
  perRule,

  /// One aggregate per severity per time bucket.
  perSeverity,

  /// One aggregate per file per time bucket.
  perFile,

  /// One aggregate per time bucket (no further breakdown).
  global,
}

/// Bucketed summary of violation activity over a fixed time window.
///
/// Returned by [ViolationTrendStore.queryAggregates]. The store
/// computes one row per bucket per `keyId`; the chart screens render
/// one or more lines / stacks / cells from the result.
@immutable
class ViolationTrendAggregate {
  /// Creates a [ViolationTrendAggregate].
  const ViolationTrendAggregate({
    required this.keyKind,
    required this.keyId,
    required this.windowStart,
    required this.windowEnd,
    required this.totalRuns,
    required this.totalViolations,
    required this.distinctViolationCount,
    required this.severityBreakdown,
  });

  /// Which dimension this aggregate is bucketed by.
  final ViolationTrendAggregateKey keyKind;

  /// Value of the bucketing key (rule id / severity name / file path),
  /// or `null` when [keyKind] is [ViolationTrendAggregateKey.global].
  final String? keyId;

  /// UTC start of the bucket's time window (inclusive).
  final DateTime windowStart;

  /// UTC end of the bucket's time window (exclusive).
  final DateTime windowEnd;

  /// Number of distinct runs whose timestamp fell into this bucket.
  final int totalRuns;

  /// Sum of violation counts across all runs in the bucket. A run
  /// reporting 5 violations and a run reporting 7 violations yield
  /// `totalViolations = 12`.
  final int totalViolations;

  /// Number of distinct violations in the bucket — collapses
  /// duplicates that fire in multiple runs into one.
  final int distinctViolationCount;

  /// Severity-grouped breakdown of [totalViolations]. The sum of the
  /// map's values equals [totalViolations].
  final Map<Severity, int> severityBreakdown;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ViolationTrendAggregate) return false;
    if (keyKind != other.keyKind) return false;
    if (keyId != other.keyId) return false;
    if (windowStart != other.windowStart) return false;
    if (windowEnd != other.windowEnd) return false;
    if (totalRuns != other.totalRuns) return false;
    if (totalViolations != other.totalViolations) return false;
    if (distinctViolationCount != other.distinctViolationCount) return false;
    if (severityBreakdown.length != other.severityBreakdown.length) {
      return false;
    }
    for (final entry in severityBreakdown.entries) {
      if (other.severityBreakdown[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    // MapEntry doesn't implement value-equality so we hash the
    // breakdown by zipping key.index with value into a single int per
    // entry and feeding the result through hashAllUnordered. This
    // keeps the hash stable regardless of iteration order.
    final breakdownHashes = <int>[
      for (final entry in severityBreakdown.entries)
        Object.hash(entry.key, entry.value),
    ];
    return Object.hash(
      keyKind,
      keyId,
      windowStart,
      windowEnd,
      totalRuns,
      totalViolations,
      distinctViolationCount,
      Object.hashAllUnordered(breakdownHashes),
    );
  }
}
