// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// How [ViolationTrendStore.applyRetention] decides which rows to
/// prune when both [maxAgeDays] and [maxRunsRetained] are
/// non-`null`.
enum TrendPruneStrategy {
  /// Delete the oldest data points first. The default — matches the
  /// intuition behind "keep the last 90 days" retention.
  oldestFirst,

  /// Delete the lowest-value points first, where "value" is a
  /// heuristic (resolved violations and singletons go before
  /// persistent runs). Reserved for future Pro tier; current
  /// implementations may treat this identically to [oldestFirst].
  lowestValueFirst,
}

/// Retention policy for the violation trend store.
///
/// Both age and run-count caps are optional; passing `null` for
/// either dimension disables that constraint. Setting both means
/// retention prunes rows that violate *either* constraint.
@immutable
class TrendRetentionPolicy {
  /// Creates a [TrendRetentionPolicy].
  const TrendRetentionPolicy({
    this.maxAgeDays,
    this.maxRunsRetained,
    this.pruneStrategy = TrendPruneStrategy.oldestFirst,
  });

  /// Default Pro policy: 90-day rolling window, up to 1000 runs,
  /// oldest-first pruning. Chosen to match SimCrux's equivalent
  /// trend-store retention configuration for cross-suite consistency.
  static const TrendRetentionPolicy proDefault = TrendRetentionPolicy(
    maxAgeDays: 90,
    maxRunsRetained: 1000,
  );

  /// Maximum age in days. Points older than `now - maxAgeDays` are
  /// pruned. `null` disables the age constraint.
  final int? maxAgeDays;

  /// Maximum number of distinct runs retained. When more than this
  /// many runs are in the store, older runs (and all their points)
  /// are pruned. `null` disables the run-count constraint.
  final int? maxRunsRetained;

  /// Tie-break strategy when both constraints are active.
  final TrendPruneStrategy pruneStrategy;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TrendRetentionPolicy) return false;
    return maxAgeDays == other.maxAgeDays &&
        maxRunsRetained == other.maxRunsRetained &&
        pruneStrategy == other.pruneStrategy;
  }

  @override
  int get hashCode => Object.hash(maxAgeDays, maxRunsRetained, pruneStrategy);

  @override
  String toString() =>
      'TrendRetentionPolicy(maxAgeDays: $maxAgeDays, '
      'maxRunsRetained: $maxRunsRetained, '
      'pruneStrategy: $pruneStrategy)';
}

/// Snapshot of current trend storage utilization, returned by
/// [ViolationTrendStore.storageStats].
@immutable
class TrendStorageStats {
  /// Creates a [TrendStorageStats].
  const TrendStorageStats({
    required this.dataPointCount,
    required this.distinctRunCount,
    this.oldestPointAt,
    this.newestPointAt,
  });

  /// Empty stats — used when the store has never ingested anything.
  static const TrendStorageStats empty = TrendStorageStats(
    dataPointCount: 0,
    distinctRunCount: 0,
  );

  /// Total number of `ViolationTrendDataPoint`s currently in the
  /// store.
  final int dataPointCount;

  /// Number of distinct runIds currently in the store.
  final int distinctRunCount;

  /// Timestamp of the oldest retained point, or `null` when empty.
  final DateTime? oldestPointAt;

  /// Timestamp of the newest retained point, or `null` when empty.
  final DateTime? newestPointAt;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TrendStorageStats) return false;
    return dataPointCount == other.dataPointCount &&
        distinctRunCount == other.distinctRunCount &&
        oldestPointAt == other.oldestPointAt &&
        newestPointAt == other.newestPointAt;
  }

  @override
  int get hashCode => Object.hash(
    dataPointCount,
    distinctRunCount,
    oldestPointAt,
    newestPointAt,
  );
}
