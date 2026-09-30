// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/models/lint_cache_key.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:meta/meta.dart';

/// One stored lint result, keyed by [key].
///
/// An entry pairs the cached [violations] list with audit metadata
/// the cache surface (stats card, invalidations dialog) needs to
/// answer questions like "which file was this for?" or "how recently
/// did we serve this from cache?".
///
/// [createdAt] is set when the entry is first stored. [lastAccessedAt]
/// is updated on every cache hit; the LRU eviction policy in the Pro
/// SQLite-backed store orders by this field when pruning to the size
/// budget.
@immutable
class LintCacheEntry {
  /// Creates a [LintCacheEntry].
  const LintCacheEntry({
    required this.key,
    required this.violations,
    required this.createdAt,
    required this.lastAccessedAt,
    required this.runDurationMs,
    required this.filePath,
  });

  /// Cache key.
  final LintCacheKey key;

  /// Cached violation list. Empty list is a valid result — "engine
  /// ran and reported zero violations" is exactly what should be
  /// cached.
  final List<Violation> violations;

  /// When the entry was first stored.
  final DateTime createdAt;

  /// When the entry was last served from the cache. Equal to
  /// [createdAt] for a freshly-stored entry. Stores update this on
  /// every successful lookup.
  final DateTime lastAccessedAt;

  /// How long the original engine invocation took to produce
  /// [violations]. Used by the stats card to estimate "time saved"
  /// (cached duration × hit count).
  final int runDurationMs;

  /// Absolute path of the source file this entry corresponds to.
  /// Used by the invalidations dialog ("this file changed → these
  /// entries were dropped") and by file-scoped invalidation.
  final String filePath;

  /// Returns a copy with overridden fields. The common case is
  /// `entry.copyWith(lastAccessedAt: DateTime.now())` on cache hit.
  LintCacheEntry copyWith({
    LintCacheKey? key,
    List<Violation>? violations,
    DateTime? createdAt,
    DateTime? lastAccessedAt,
    int? runDurationMs,
    String? filePath,
  }) {
    return LintCacheEntry(
      key: key ?? this.key,
      violations: violations ?? this.violations,
      createdAt: createdAt ?? this.createdAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      runDurationMs: runDurationMs ?? this.runDurationMs,
      filePath: filePath ?? this.filePath,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LintCacheEntry) return false;
    if (other.key != key) return false;
    if (other.createdAt != createdAt) return false;
    if (other.lastAccessedAt != lastAccessedAt) return false;
    if (other.runDurationMs != runDurationMs) return false;
    if (other.filePath != filePath) return false;
    if (other.violations.length != violations.length) return false;
    for (var i = 0; i < violations.length; i++) {
      if (other.violations[i] != violations[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    key,
    createdAt,
    lastAccessedAt,
    runDurationMs,
    filePath,
    Object.hashAll(violations),
  );
}
