// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Cache-wide statistics aggregate.
///
/// Returned by [LintRunCacheService.stats] and consumed by the
/// Settings → Lint Cache section's stats card. Every counter is
/// monotonic across the cache's lifetime (hits / misses /
/// invalidations) except the entry-shaped fields ([entryCount],
/// [approximateBytes], [oldestEntryAt], [newestEntryAt]) which
/// reflect the *current* state.
///
/// [estimatedTimeSavedMs] is computed by the store as the sum of
/// each cached entry's `runDurationMs * (lookups served from that
/// entry)`. The Pro SQLite store tracks per-entry hit counts in a
/// dedicated column; the open-core no-op default emits zero.
///
/// All values are advisory. The cache stats query never throws — on
/// storage corruption it degrades to zero counters and logs a
/// diagnostic.
@immutable
class LintCacheStats {
  /// Creates a [LintCacheStats].
  const LintCacheStats({
    required this.entryCount,
    required this.approximateBytes,
    required this.hitCount,
    required this.missCount,
    required this.invalidationCount,
    required this.oldestEntryAt,
    required this.newestEntryAt,
    required this.averageRunDurationMs,
    required this.estimatedTimeSavedMs,
  });

  /// Empty stats — used as the no-op default and as the starting
  /// point for tests.
  static const LintCacheStats empty = LintCacheStats(
    entryCount: 0,
    approximateBytes: 0,
    hitCount: 0,
    missCount: 0,
    invalidationCount: 0,
    oldestEntryAt: null,
    newestEntryAt: null,
    averageRunDurationMs: 0,
    estimatedTimeSavedMs: 0,
  );

  /// Total cached entries.
  final int entryCount;

  /// Best-effort on-disk byte usage. Implementations are free to
  /// approximate (the SQLite store reports `page_count * page_size`).
  final int approximateBytes;

  /// Cache hits since the store opened.
  final int hitCount;

  /// Cache misses since the store opened.
  final int missCount;

  /// Invalidation events processed since the store opened.
  final int invalidationCount;

  /// `createdAt` of the oldest stored entry, or `null` when the
  /// cache is empty.
  final DateTime? oldestEntryAt;

  /// `createdAt` of the newest stored entry, or `null` when the
  /// cache is empty.
  final DateTime? newestEntryAt;

  /// Mean `runDurationMs` across all cached entries.
  final int averageRunDurationMs;

  /// Cumulative "time saved" estimate (cached run duration × hit
  /// count).
  final int estimatedTimeSavedMs;

  /// Hit rate as a fraction in `[0, 1]`. Returns 0 when there have
  /// been no lookups.
  double get hitRate {
    final total = hitCount + missCount;
    if (total == 0) return 0;
    return hitCount / total;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LintCacheStats) return false;
    return other.entryCount == entryCount &&
        other.approximateBytes == approximateBytes &&
        other.hitCount == hitCount &&
        other.missCount == missCount &&
        other.invalidationCount == invalidationCount &&
        other.oldestEntryAt == oldestEntryAt &&
        other.newestEntryAt == newestEntryAt &&
        other.averageRunDurationMs == averageRunDurationMs &&
        other.estimatedTimeSavedMs == estimatedTimeSavedMs;
  }

  @override
  int get hashCode => Object.hash(
    entryCount,
    approximateBytes,
    hitCount,
    missCount,
    invalidationCount,
    oldestEntryAt,
    newestEntryAt,
    averageRunDurationMs,
    estimatedTimeSavedMs,
  );

  @override
  String toString() =>
      'LintCacheStats('
      'entries: $entryCount, '
      'hits: $hitCount, '
      'misses: $missCount, '
      'invalidations: $invalidationCount)';
}
