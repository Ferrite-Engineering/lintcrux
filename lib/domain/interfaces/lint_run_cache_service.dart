// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/models/lint_cache_entry.dart';
import 'package:lintcrux/domain/models/lint_cache_invalidation_event.dart';
import 'package:lintcrux/domain/models/lint_cache_key.dart';
import 'package:lintcrux/domain/models/lint_cache_stats.dart';

/// Caches lint engine results so repeat runs over unchanged inputs
/// don't reinvoke the engine subprocess.
///
/// Open Core ships [NoopLintRunCacheService] — every [lookup] returns
/// `null` (forcing a fresh run), every [store] silently discards the
/// entry, every [invalidate] is a no-op, [stats] returns
/// [LintCacheStats.empty], and [invalidations] never emits.
///
/// The Pro overlay supplies `SqliteLintRunCacheService` — a per-
/// project SQLite-backed implementation that persists entries to
/// `<projectPath>/.lintcrux/cache.db`, enforces a size budget via
/// LRU eviction, and surfaces invalidation events so the Settings
/// UI's invalidations log + stats card stay live.
///
/// The cache surface is **only** consulted by the lint runner during
/// `runAll` / `runIncremental` paths. Action-driven engine
/// invocations (Verible auto-fix dry-run, the parser-comparison
/// diagnostic) call engines directly and do not flow through the
/// cache — those are tools, not lint runs.
abstract class LintRunCacheService {
  /// Returns the stored entry for [key], or `null` if the cache
  /// does not contain a matching entry.
  ///
  /// Successful lookups update the entry's `lastAccessedAt` so
  /// LRU eviction sees recently-served entries as warm.
  Future<LintCacheEntry?> lookup(LintCacheKey key);

  /// Atomically inserts or replaces [entry] in the cache.
  ///
  /// Stores enforce the configured size budget here — when the
  /// total approximate bytes exceeds the budget, the oldest
  /// entries (by `lastAccessedAt`) are pruned to make room before
  /// the new entry is stored, and a
  /// [LintCacheInvalidationRetentionPrune] event is emitted on
  /// [invalidations].
  Future<void> store(LintCacheEntry entry);

  /// Removes entries matching the [event]'s scope. The store emits
  /// the same event back on [invalidations] with `entriesRemoved`
  /// populated so observers can render a faithful log.
  ///
  /// Pass the appropriate subtype:
  ///   * [LintCacheInvalidationFileChanged] — remove every entry
  ///     whose `filePath` matches `event.filePath`. Used by the
  ///     file-watcher integration.
  ///   * [LintCacheInvalidationConfigChanged] — remove every entry
  ///     whose `key.engineId` matches `event.engineId`. Used when
  ///     `LintProject` config changes.
  ///   * [LintCacheInvalidationEngineVersionChanged] — remove
  ///     every entry for `event.engineId` whose
  ///     `key.engineVersion` matches `event.oldVersion`. Used when
  ///     the engine reports a new `--version` on subsequent runs.
  ///   * [LintCacheInvalidationManualClear] — remove everything
  ///     (equivalent to [clearAll], but emits a manual-clear
  ///     event rather than synthesizing one).
  ///   * [LintCacheInvalidationRetentionPrune] — typically
  ///     emitted by the store itself; passing one in is a no-op.
  ///
  /// The `entriesRemoved` field on the inbound event is ignored;
  /// the store recomputes it and re-emits the event with the true
  /// count.
  Future<void> invalidate(LintCacheInvalidationEvent event);

  /// Returns a snapshot of the cache's current state. Cheap to
  /// call — the Settings stats card consumes this on demand via a
  /// FutureProvider that refreshes when [invalidations] ticks.
  Future<LintCacheStats> stats();

  /// Wipes every entry. Equivalent to passing a
  /// [LintCacheInvalidationManualClear] to [invalidate] with
  /// `reason: 'clear_all'`. Used by the "Clear cache now" action.
  Future<void> clearAll();

  /// Broadcast stream of invalidation events. The Pro overlay's
  /// invalidations dialog subscribes to this; stats panels also
  /// listen to refresh their numbers without polling.
  ///
  /// Implementations close the stream on disposal.
  Stream<LintCacheInvalidationEvent> get invalidations;
}

/// Open Core default. Every operation is a silent no-op so the
/// runner integration can be written once and behave correctly on
/// both tiers — Open Core simply doesn't benefit from caching.
class NoopLintRunCacheService implements LintRunCacheService {
  /// Creates a [NoopLintRunCacheService].
  const NoopLintRunCacheService();

  @override
  Future<LintCacheEntry?> lookup(LintCacheKey key) async => null;

  @override
  Future<void> store(LintCacheEntry entry) async {}

  @override
  Future<void> invalidate(LintCacheInvalidationEvent event) async {}

  @override
  Future<LintCacheStats> stats() async => LintCacheStats.empty;

  @override
  Future<void> clearAll() async {}

  @override
  Stream<LintCacheInvalidationEvent> get invalidations =>
      const Stream<LintCacheInvalidationEvent>.empty();
}
