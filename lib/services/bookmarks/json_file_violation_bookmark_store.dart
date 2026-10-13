// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lintcrux/domain/interfaces/violation_bookmark_store.dart';
import 'package:lintcrux/domain/models/bookmarked_violation.dart';
import 'package:lintcrux/services/persistence/atomic_json_file.dart';

/// The [ViolationBookmarkStore] backed by a versionable JSON file
/// alongside the project source tree (typically
/// `<project-root>/.lintcrux-bookmarks.json`).
///
/// File format (v2, JSON):
///
/// ```json
/// {
///   "version": 2,
///   "bookmarks": [
///     { "version": 2, "id": "...", "fingerprint": "...", ... },
///     ...
///   ]
/// }
/// ```
///
/// Version 1 files hashed the absolute file path into each fingerprint,
/// so a bookmark only matched in the checkout that created it. [load]
/// still reads them and upgrades every bookmark against [projectRoot]
/// (`BookmarkedViolation.withProjectFingerprint`); the next write stores
/// version 2.
///
/// Bookmark identity is the [BookmarkedViolation.fingerprint] (same
/// FNV-1a hash scheme as `BaselineFingerprint`), so a bookmark
/// survives line shifts caused by surrounding edits. The store
/// maintains an in-memory fingerprint → bookmark map for O(1) lookup
/// by the violations-table bookmark column.
///
/// **Stale-detection.** [updateLastSeenForRun] is invoked by the
/// tab's `BookmarkFreshnessNotifier` after every completed lint run;
/// bookmarks whose fingerprint appears among the run's violations get
/// their `lastSeenRunId` refreshed (no
/// `updatedAt` bump — stale-detection is informational). Bookmarks
/// whose fingerprint does NOT appear simply keep their previous
/// `lastSeenRunId`, which the panel renders as a "stale" indicator
/// when it lags behind the latest run.
///
/// Atomic writes (temp file + rename) keep the store crash-safe.
///
/// The file name, location, schema and fingerprint scheme are the ones
/// earlier releases wrote, so an existing bookmark file loads unchanged.
class JsonFileViolationBookmarkStore implements ViolationBookmarkStore {
  /// Creates a store that reads/writes [file] for the project rooted at
  /// [projectRoot].
  JsonFileViolationBookmarkStore(this.file, {required this.projectRoot});

  /// Persistent JSON file. Need not exist — [load] tolerates a missing
  /// file by treating the store as empty.
  final File file;

  /// Root of the project the bookmarks belong to. Version 1 fingerprints
  /// are recomputed against it on [load].
  final String projectRoot;

  /// In-memory map of bookmark id → [BookmarkedViolation]. Holds the
  /// authoritative list once [load] resolves.
  final Map<String, BookmarkedViolation> _byId =
      <String, BookmarkedViolation>{};

  /// In-memory index of fingerprint → [BookmarkedViolation]. Keeps
  /// [lookupByFingerprint] O(1).
  final Map<String, BookmarkedViolation> _byFingerprint =
      <String, BookmarkedViolation>{};

  /// Why the last [load] failed, or null when it succeeded.
  ///
  /// While set, every write is refused: the file holds the team's committed
  /// bookmarks and this store holds none of them, so a write would replace the whole
  /// file with whatever was changed since.
  Object? get loadError => _loadError;
  Object? _loadError;

  void _refuseWhileUnreadable() {
    final error = _loadError;
    if (error == null) return;
    throw StateError(
      'The bookmark file ${file.path} could not be read ($error), so it is '
      'not being written over. Repair or restore it, then reopen the '
      'project.',
    );
  }

  final StreamController<void> _events = StreamController<void>.broadcast();

  /// Current on-disk schema version. Bumped whenever the file shape
  /// changes in a backward-incompatible way.
  static const int currentVersion = 2;

  /// The file version whose fingerprints hashed absolute paths. Read and
  /// upgraded on [load].
  static const int _absolutePathVersion = 1;

  /// Loads bookmarks from [file] if it exists. A missing file is not
  /// an error — the store is simply empty.
  ///
  /// Throws [FormatException] when the file exists but contains JSON
  /// neither the v1 nor the v2 reader can interpret.
  Future<void> load() async {
    _byId.clear();
    _byFingerprint.clear();
    // Parsed aside and merged whole. A malformed entry partway used to leave
    // the ones before it loaded, and the stale-detection write after the next
    // lint run then deleted every bookmark after it from the file. Merged
    // rather than assigned, so a bookmark added while the file was being read
    // is kept.
    final loaded = <String, BookmarkedViolation>{};
    try {
      await _parseInto(loaded);
    } on Object catch (error) {
      _loadError = error;
      rethrow;
    }
    _loadError = null;
    for (final bm in loaded.values) {
      if (_byId.containsKey(bm.id) ||
          _byFingerprint.containsKey(bm.fingerprint)) {
        continue;
      }
      _byId[bm.id] = bm;
      _byFingerprint[bm.fingerprint] = bm;
    }
    // Consumers that took a snapshot while the file was being read would
    // otherwise show no bookmarks until the next write.
    if (!_events.isClosed) _events.add(null);
  }

  Future<void> _parseInto(Map<String, BookmarkedViolation> loaded) async {
    if (!file.existsSync()) return;
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException(
        'Bookmark file must be a JSON object; got ${decoded.runtimeType}',
      );
    }
    final version = decoded['version'];
    if (version is! int) {
      throw const FormatException(
        "Bookmark file missing required 'version' field",
      );
    }
    if (version != currentVersion && version != _absolutePathVersion) {
      throw FormatException(
        'Unsupported bookmark file schema version: $version '
        '(this build understands v$_absolutePathVersion and '
        'v$currentVersion)',
      );
    }
    final entriesRaw = decoded['bookmarks'];
    if (entriesRaw is! List) {
      throw const FormatException(
        "Bookmark file 'bookmarks' field must be a list",
      );
    }
    for (final entry in entriesRaw) {
      if (entry is! Map<String, dynamic>) continue;
      final bm = BookmarkedViolation.fromJson(
        entry,
      ).withProjectFingerprint(projectRoot);
      loaded[bm.id] = bm;
    }
  }

  @override
  Future<List<BookmarkedViolation>> listAll() async {
    final list = _byId.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List<BookmarkedViolation>.unmodifiable(list);
  }

  @override
  Future<BookmarkedViolation?> lookupByFingerprint(String fingerprint) async {
    return _byFingerprint[fingerprint];
  }

  @override
  Future<void> addOrUpdate(BookmarkedViolation bookmark) async {
    _refuseWhileUnreadable();
    final existing = _byId[bookmark.id];
    if (existing == null) {
      // Insert path — reject if another bookmark already owns the
      // same fingerprint (each violation gets at most one bookmark).
      final fingerprintCollision = _byFingerprint[bookmark.fingerprint];
      if (fingerprintCollision != null &&
          fingerprintCollision.id != bookmark.id) {
        throw ArgumentError.value(
          bookmark.fingerprint,
          'bookmark.fingerprint',
          'a different bookmark already exists for this violation '
              '(id: ${fingerprintCollision.id})',
        );
      }
    }
    if (existing != null) {
      _byFingerprint.remove(existing.fingerprint);
    }
    _byId[bookmark.id] = bookmark;
    _byFingerprint[bookmark.fingerprint] = bookmark;
    await _writeAtomic();
    // The write can outlive the store when its trigger is fire-and-forget
    // (the stale-detection listener) and the project closes mid-write;
    // adding to a closed controller throws. Mirrors the guard on the lint
    // cache proxy's invalidation relay.
    if (!_events.isClosed) _events.add(null);
  }

  @override
  Future<void> remove(String bookmarkId) async {
    _refuseWhileUnreadable();
    final existing = _byId.remove(bookmarkId);
    if (existing == null) return; // silent no-op on unknown id
    _byFingerprint.remove(existing.fingerprint);
    await _writeAtomic();
    // The write can outlive the store when its trigger is fire-and-forget
    // (the stale-detection listener) and the project closes mid-write;
    // adding to a closed controller throws. Mirrors the guard on the lint
    // cache proxy's invalidation relay.
    if (!_events.isClosed) _events.add(null);
  }

  @override
  Stream<void> get changed => _events.stream;

  /// Updates [BookmarkedViolation.lastSeenRunId] to [runId] on every
  /// bookmark whose fingerprint is in [firingFingerprints]. Bookmarks
  /// whose fingerprint does NOT appear are left untouched (the panel
  /// surfaces them as "stale" based on the lag in `lastSeenRunId`).
  ///
  /// The fingerprint match key is computed from the violation's
  /// `(ruleId, filePath, message)` triple and the project root via
  /// `BaselineFingerprint.forProject`, so the bookmark fingerprint
  /// scheme stays identical to the baseline scheme.
  ///
  /// Caller is responsible for passing the precomputed fingerprint
  /// set; the store does not depend on the fingerprint algorithm
  /// directly. This keeps the store testable without dragging in the
  /// `BaselineFingerprint` machinery.
  Future<void> updateLastSeenForRun({
    required String runId,
    required Set<String> firingFingerprints,
  }) async {
    // Automatic bookkeeping after every run: with the file unreadable there
    // is nothing loaded to update, and nothing may be written.
    if (_loadError != null) return;
    var mutated = false;
    for (final entry in _byId.entries.toList()) {
      final bm = entry.value;
      if (!firingFingerprints.contains(bm.fingerprint)) continue;
      if (bm.lastSeenRunId == runId) continue;
      // Stale-detection touches lastSeenRunId only — NOT updatedAt
      // (updatedAt is reserved for user-initiated edits).
      final updated = bm.copyWith(lastSeenRunId: runId);
      _byId[entry.key] = updated;
      _byFingerprint[updated.fingerprint] = updated;
      mutated = true;
    }
    if (mutated) {
      try {
        await _writeAtomic();
      } finally {
        // The bookmarks above changed in memory whether or not the file
        // could be written (a read-only checkout refuses it), and the table
        // reads memory. Without the event it keeps showing the old freshness.
        if (!_events.isClosed) _events.add(null);
      }
    }
  }

  /// Closes the broadcast stream. Call from `ref.onDispose`.
  Future<void> dispose() => _events.close();

  Future<void> _writeAtomic() async {
    _refuseWhileUnreadable();
    final payload = <String, Object?>{
      'version': currentVersion,
      'bookmarks': <Map<String, Object?>>[
        for (final bm in _byId.values) bm.toJson(),
      ],
    };
    // Crash-safe atomic write (temp file + rename).
    await writeJsonAtomic(file, payload);
  }
}
