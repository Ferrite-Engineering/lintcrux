// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/models/bookmarked_violation.dart';

/// Persistence interface for the per-project violation bookmark set.
///
/// Open Core ships [NoopViolationBookmarkStore] (`listAll` returns `[]`,
/// mutations no-op silently) — the bookmark feature is Pro. The Pro overlay
/// supplies `JsonFileViolationBookmarkStore` which reads/writes
/// `<project-root>/.lintcrux-bookmarks.json` with schema-versioned content and
/// a stale-detection hook that runs on every project-wide
/// [LintRunCompletionEvent].
///
/// Bookmark identity is the [BookmarkedViolation.fingerprint] (the
/// same fingerprint the baseline system uses, computed via
/// [BaselineFingerprint.compute]). Tooling that needs O(1) "is this
/// violation bookmarked?" lookup uses [lookupByFingerprint].
abstract class ViolationBookmarkStore {
  /// Returns every bookmark, sorted by [BookmarkedViolation.createdAt]
  /// ascending. Implementations may cache the list and stream
  /// invalidations through [changed].
  Future<List<BookmarkedViolation>> listAll();

  /// Returns the bookmark whose [BookmarkedViolation.fingerprint]
  /// matches [fingerprint], or `null` when no such bookmark exists.
  /// Used by the violations-table bookmark column for the
  /// is-it-bookmarked check.
  Future<BookmarkedViolation?> lookupByFingerprint(String fingerprint);

  /// Saves [bookmark] — creates if [bookmark.id] is unknown, updates
  /// otherwise. Implementations must reject duplicate fingerprints
  /// on insert (each violation gets at most one bookmark).
  Future<void> addOrUpdate(BookmarkedViolation bookmark);

  /// Removes the bookmark with [bookmarkId]. Silent no-op when
  /// the id is unknown.
  Future<void> remove(String bookmarkId);

  /// Stream that emits on every successful mutation. Used by the
  /// bookmark column / panel to refresh without polling.
  Stream<void> get changed;
}

/// Open-core default that holds no bookmarks and silently no-ops on
/// every mutation. The seam is still wired so consumers (the
/// bookmark column, the count badge, the panel) can read from the
/// provider without crashing in the open-core build.
class NoopViolationBookmarkStore implements ViolationBookmarkStore {
  /// Creates a [NoopViolationBookmarkStore].
  const NoopViolationBookmarkStore();

  @override
  Future<List<BookmarkedViolation>> listAll() async =>
      const <BookmarkedViolation>[];

  @override
  Future<BookmarkedViolation?> lookupByFingerprint(String fingerprint) async =>
      null;

  @override
  Future<void> addOrUpdate(BookmarkedViolation bookmark) async {
    // Intentionally silent: the bookmark feature is Pro; activating
    // it in open-core should not throw at the call site (the Pro
    // overlay's selector chips / panel are not rendered, so this is
    // unreachable from the UI anyway). A throw would be a defect.
  }

  @override
  Future<void> remove(String bookmarkId) async {
    // See `addOrUpdate` — silent no-op for the same reason.
  }

  @override
  Stream<void> get changed => const Stream<void>.empty();
}
