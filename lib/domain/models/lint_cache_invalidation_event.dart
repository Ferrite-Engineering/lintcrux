// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// One event describing a cache invalidation that just occurred.
///
/// Emitted by [LintRunCacheService.invalidations]. The invalidations
/// dialog renders a rolling log of these events with timestamp +
/// kind-specific summary so the user can answer "why did my cache get
/// cleared?".
///
/// Sealed: every subtype is a `const`-constructible record carrying
/// the data the kind's row needs. Matched via Dart's pattern matching
/// (`switch (event) { case FileChanged ... }`).
@immutable
sealed class LintCacheInvalidationEvent {
  /// Creates a [LintCacheInvalidationEvent].
  const LintCacheInvalidationEvent({required this.occurredAt});

  /// When the invalidation occurred.
  final DateTime occurredAt;
}

/// A source file changed on disk — entries whose `filePath` matched
/// were dropped.
@immutable
class LintCacheInvalidationFileChanged extends LintCacheInvalidationEvent {
  /// Creates a [LintCacheInvalidationFileChanged].
  const LintCacheInvalidationFileChanged({
    required super.occurredAt,
    required this.filePath,
    required this.entriesRemoved,
  });

  /// Absolute path of the file that changed.
  final String filePath;

  /// How many cache entries the store removed in response.
  final int entriesRemoved;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LintCacheInvalidationFileChanged &&
          other.occurredAt == occurredAt &&
          other.filePath == filePath &&
          other.entriesRemoved == entriesRemoved);

  @override
  int get hashCode => Object.hash(occurredAt, filePath, entriesRemoved);
}

/// An engine's configuration changed — entries for that engine were
/// dropped.
@immutable
class LintCacheInvalidationConfigChanged extends LintCacheInvalidationEvent {
  /// Creates a [LintCacheInvalidationConfigChanged].
  const LintCacheInvalidationConfigChanged({
    required super.occurredAt,
    required this.engineId,
    required this.entriesRemoved,
  });

  /// Engine whose config changed.
  final String engineId;

  /// How many cache entries the store removed in response.
  final int entriesRemoved;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LintCacheInvalidationConfigChanged &&
          other.occurredAt == occurredAt &&
          other.engineId == engineId &&
          other.entriesRemoved == entriesRemoved);

  @override
  int get hashCode => Object.hash(occurredAt, engineId, entriesRemoved);
}

/// An engine's binary version changed — entries for the prior
/// version were dropped.
@immutable
class LintCacheInvalidationEngineVersionChanged
    extends LintCacheInvalidationEvent {
  /// Creates a [LintCacheInvalidationEngineVersionChanged].
  const LintCacheInvalidationEngineVersionChanged({
    required super.occurredAt,
    required this.engineId,
    required this.oldVersion,
    required this.newVersion,
    required this.entriesRemoved,
  });

  /// Engine whose version changed.
  final String engineId;

  /// Previous engine version.
  final String oldVersion;

  /// New engine version.
  final String newVersion;

  /// How many cache entries the store removed.
  final int entriesRemoved;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LintCacheInvalidationEngineVersionChanged &&
          other.occurredAt == occurredAt &&
          other.engineId == engineId &&
          other.oldVersion == oldVersion &&
          other.newVersion == newVersion &&
          other.entriesRemoved == entriesRemoved);

  @override
  int get hashCode => Object.hash(
    occurredAt,
    engineId,
    oldVersion,
    newVersion,
    entriesRemoved,
  );
}

/// User-triggered "Clear cache now" (or similar). [reason] describes
/// the trigger source (e.g. `"manual_clear_all"`, `"recents_purge"`).
@immutable
class LintCacheInvalidationManualClear extends LintCacheInvalidationEvent {
  /// Creates a [LintCacheInvalidationManualClear].
  const LintCacheInvalidationManualClear({
    required super.occurredAt,
    required this.reason,
    required this.entriesRemoved,
  });

  /// Human-readable trigger description.
  final String reason;

  /// How many entries the store wiped.
  final int entriesRemoved;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LintCacheInvalidationManualClear &&
          other.occurredAt == occurredAt &&
          other.reason == reason &&
          other.entriesRemoved == entriesRemoved);

  @override
  int get hashCode => Object.hash(occurredAt, reason, entriesRemoved);
}

/// LRU eviction kicked in because the cache exceeded its size budget.
@immutable
class LintCacheInvalidationRetentionPrune extends LintCacheInvalidationEvent {
  /// Creates a [LintCacheInvalidationRetentionPrune].
  const LintCacheInvalidationRetentionPrune({
    required super.occurredAt,
    required this.entriesRemoved,
    required this.oldestRemovedAt,
    required this.newestRemovedAt,
  });

  /// How many entries the prune dropped.
  final int entriesRemoved;

  /// `createdAt` of the oldest entry that was pruned.
  final DateTime oldestRemovedAt;

  /// `createdAt` of the newest entry that was pruned (always older
  /// than entries that survived).
  final DateTime newestRemovedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LintCacheInvalidationRetentionPrune &&
          other.occurredAt == occurredAt &&
          other.entriesRemoved == entriesRemoved &&
          other.oldestRemovedAt == oldestRemovedAt &&
          other.newestRemovedAt == newestRemovedAt);

  @override
  int get hashCode => Object.hash(
    occurredAt,
    entriesRemoved,
    oldestRemovedAt,
    newestRemovedAt,
  );
}
