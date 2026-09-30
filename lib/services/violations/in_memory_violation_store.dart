// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:collection';

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/violation_store.dart';
import 'package:lintcrux/domain/models/violation.dart';

/// Pure in-memory implementation of [ViolationStore].
///
/// The table, status bar, inspector, and export pipeline
/// all read from this store. Each mutation keeps four indices in sync —
/// by severity, by engine, by engine-namespaced rule id, and by absolute
/// file path — so [filter] and the per-index getters are O(matches), not
/// O(total).
///
/// Inserts are O(1) amortised. Bulk replacements
/// ([replaceFromEngine] / [replacePartialFromEngine]) are O(N) in the
/// combined size of the removed set, the inserted set, and the buckets
/// they touch: removals are batched into one linear pass per distinct
/// affected index key against an identity drop-set, never one bucket
/// scan per removed violation. The per-engine index supplies the removed
/// set in O(1) without scanning the whole store.
///
/// The batching matters because the severity index aggregates across
/// engines: a per-violation removal loop would scan an
/// all-engines-wide bucket once per removed row, which is quadratic on
/// the UI isolate for every re-run and every cache hit.
///
/// The exposed index maps and lists are unmodifiable views over the live
/// internal state. The internal mutable storage is never handed out to
/// callers.
///
/// Streaming writes ([addStreaming]) update the indices incrementally;
/// [completeStreaming] is the boundary marker that drives the
/// [RunCompleted] event.
class InMemoryViolationStore implements ViolationStore {
  final List<Violation> _all = <Violation>[];

  final Map<Severity, List<Violation>> _bySeverity =
      <Severity, List<Violation>>{};
  final Map<String, List<Violation>> _byEngine = <String, List<Violation>>{};
  final Map<String, List<Violation>> _byRule = <String, List<Violation>>{};
  final Map<String, List<Violation>> _byFile = <String, List<Violation>>{};

  final StreamController<ViolationStoreEvent> _events =
      StreamController<ViolationStoreEvent>.broadcast();

  int _lastRemovalScans = 0;

  /// Test / diagnostic instrumentation: the number of `_all` and index
  /// *element visits* performed by the removal phase of the most recent
  /// bulk replacement ([replaceFromEngine] / [replacePartialFromEngine]).
  /// Reset to zero at the start of every bulk replacement.
  ///
  /// This is the deterministic, CPU-contention-immune proxy the
  /// complexity guard asserts on instead of wall-clock time. The batched
  /// removal path visits each affected bucket element exactly once — one
  /// linear pass per distinct affected index key — so this count is O(N)
  /// in the removed corpus. A per-violation removal loop would rescan an
  /// aggregate (cross-engine) bucket once per removed row, making the
  /// count O(N²); the guard reads that difference off this counter
  /// without measuring time, so a busy CI core cannot perturb it.
  ///
  /// It counts *scans*, not the removals themselves: `List.removeWhere`
  /// (and `List.remove`) walk the whole candidate list, so the number of
  /// elements a removal pass touches — not the number it drops — is the
  /// intrinsic cost that separates linear batching from a quadratic loop.
  int get lastRemovalScans => _lastRemovalScans;

  @override
  Stream<ViolationStoreEvent> get events => _events.stream;

  @override
  List<Violation> get all => List<Violation>.unmodifiable(_all);

  @override
  int get count => _all.length;

  @override
  bool get isEmpty => _all.isEmpty;

  @override
  List<Violation> byEngineOf(String engineId) =>
      UnmodifiableListView<Violation>(
        _byEngine[engineId] ?? const <Violation>[],
      );

  @override
  Map<Severity, List<Violation>> get bySeverity => _readOnlyView(_bySeverity);

  @override
  Map<String, List<Violation>> get byEngine => _readOnlyView(_byEngine);

  @override
  Map<String, List<Violation>> get byRule => _readOnlyView(_byRule);

  @override
  Map<String, List<Violation>> get byFile => _readOnlyView(_byFile);

  @override
  void replacePartialFromEngine(
    String engineId,
    Set<String> changedFiles,
    List<Violation> newViolations,
  ) {
    _lastRemovalScans = 0;
    final existing = _byEngine[engineId];
    if (existing != null && existing.isNotEmpty) {
      // Drop the engine's existing violations that live in changed
      // files; everything else stays. Build an identity set so the
      // `_all` filter is O(1) per element.
      final toDrop = <Violation>[
        for (final v in existing)
          if (changedFiles.contains(v.location.file)) v,
      ];
      if (toDrop.isNotEmpty) {
        final dropSet = Set<Violation>.identity()..addAll(toDrop);
        _lastRemovalScans += _all.length;
        _all.removeWhere(dropSet.contains);
        _lastRemovalScans += _removeBatchFromIndex(
          _bySeverity,
          <Severity>{for (final v in toDrop) v.severity},
          dropSet,
        );
        _lastRemovalScans += _removeBatchFromIndex(
          _byRule,
          <String>{for (final v in toDrop) v.ruleId},
          dropSet,
        );
        _lastRemovalScans += _removeBatchFromIndex(
          _byFile,
          <String>{for (final v in toDrop) v.location.file},
          dropSet,
        );
        // Rebuild the engine bucket from the survivors.
        existing.removeWhere(dropSet.contains);
        if (existing.isEmpty) {
          _byEngine.remove(engineId);
        }
      }
    }

    for (final v in newViolations) {
      assert(
        v.engineId == engineId,
        'Violation.engineId (${v.engineId}) must match '
        'replacePartialFromEngine bucket ($engineId)',
      );
      _insert(v);
    }

    _events.add(
      EngineReplaced(engineId, (_byEngine[engineId] ?? const []).length),
    );
  }

  @override
  void replaceFromEngine(String engineId, List<Violation> violations) {
    // Remove existing violations for this engine from all indices and
    // from `_all`. The `_byEngine` index gives us the existing set in O(1).
    _lastRemovalScans = 0;
    final existing = _byEngine.remove(engineId);
    if (existing != null && existing.isNotEmpty) {
      // Build an identity set for O(1) lookup during the `_all` filter.
      final toDrop = Set<Violation>.identity()..addAll(existing);
      _lastRemovalScans += _all.length;
      _all.removeWhere(toDrop.contains);
      // One pass per *distinct* affected key, not one pass per removed
      // violation: severity buckets aggregate across engines, so a
      // per-violation scan degenerates to O(removed x bucket).
      _lastRemovalScans += _removeBatchFromIndex(
        _bySeverity,
        <Severity>{for (final v in existing) v.severity},
        toDrop,
      );
      _lastRemovalScans += _removeBatchFromIndex(
        _byRule,
        <String>{for (final v in existing) v.ruleId},
        toDrop,
      );
      _lastRemovalScans += _removeBatchFromIndex(
        _byFile,
        <String>{for (final v in existing) v.location.file},
        toDrop,
      );
    }

    // Add the new violations. Engine-id consistency is asserted in debug
    // builds — if a caller passes a Violation whose engineId differs from
    // the bucket it's being inserted into, the indices would corrupt.
    for (final v in violations) {
      assert(
        v.engineId == engineId,
        'Violation.engineId (${v.engineId}) must match '
        'replaceFromEngine bucket ($engineId)',
      );
      _insert(v);
    }

    _events.add(EngineReplaced(engineId, violations.length));
  }

  @override
  void addStreaming(Violation v) {
    _insert(v);
    _events.add(ViolationAdded(v));
  }

  @override
  void completeStreaming(String engineId) {
    _events.add(RunCompleted(engineId));
  }

  @override
  List<Violation> filter(ViolationFilter filter) {
    // Pick the most selective index up front so we scan the smallest
    // candidate set. Severity is usually the coarsest dimension; engine
    // is next. The other dimensions cascade as in-place tests.
    Iterable<Violation> candidates;
    if (filter.severities != null && filter.severities!.isNotEmpty) {
      candidates = filter.severities!.expand(
        (s) => _bySeverity[s] ?? const <Violation>[],
      );
    } else if (filter.engineIds != null && filter.engineIds!.isNotEmpty) {
      candidates = filter.engineIds!.expand(
        (id) => _byEngine[id] ?? const <Violation>[],
      );
    } else {
      candidates = _all;
    }

    final ruleNeedle = filter.ruleSubstring?.toLowerCase();
    final glob = filter.fileGlob;
    final globPattern = (glob == null || glob.isEmpty) ? null : _glob(glob);

    final out = <Violation>[];
    for (final v in candidates) {
      if (filter.severities != null &&
          !filter.severities!.contains(v.severity)) {
        continue;
      }
      if (filter.engineIds != null && !filter.engineIds!.contains(v.engineId)) {
        continue;
      }
      if (!filter.includeSuppressed && v.isSuppressed) {
        continue;
      }
      if (ruleNeedle != null && ruleNeedle.isNotEmpty) {
        if (!v.ruleId.toLowerCase().contains(ruleNeedle) &&
            !v.message.toLowerCase().contains(ruleNeedle)) {
          continue;
        }
      }
      if (globPattern != null && !globPattern.hasMatch(v.location.file)) {
        continue;
      }
      out.add(v);
    }
    return out;
  }

  /// Disposes the broadcast stream. Subsequent mutations are silently
  /// ignored downstream once the controller is closed; in tests this is
  /// usually unnecessary because the store goes out of scope, but a
  /// `dispose()` is provided for symmetry with anywhere a Riverpod
  /// `Notifier` would call it.
  Future<void> dispose() async {
    await _events.close();
  }

  // ─── internals ──────────────────────────────────────────────────────────

  void _insert(Violation v) {
    _all.add(v);
    (_bySeverity[v.severity] ??= <Violation>[]).add(v);
    (_byEngine[v.engineId] ??= <Violation>[]).add(v);
    (_byRule[v.ruleId] ??= <Violation>[]).add(v);
    (_byFile[v.location.file] ??= <Violation>[]).add(v);
  }

  /// Drops every violation in [dropSet] from the buckets named by [keys],
  /// one linear pass per distinct key. Returns the number of bucket
  /// *element visits* performed (the sum of the touched bucket lengths) —
  /// the intrinsic linear-vs-quadratic cost the complexity guard reads
  /// off [lastRemovalScans].
  ///
  /// [keys] must be de-duplicated by the caller — a repeated key re-scans
  /// a bucket that has already been filtered, which is exactly the
  /// quadratic behaviour this batch form exists to avoid.
  ///
  /// [dropSet] must be an identity set (`Set<Violation>.identity()`) so
  /// two semantically equal violations don't collapse into one removal.
  static int _removeBatchFromIndex<K>(
    Map<K, List<Violation>> index,
    Set<K> keys,
    Set<Violation> dropSet,
  ) {
    var scans = 0;
    for (final key in keys) {
      final bucket = index[key];
      if (bucket == null) continue;
      // removeWhere walks the whole bucket; that walk is the cost.
      scans += bucket.length;
      bucket.removeWhere(dropSet.contains);
      if (bucket.isEmpty) {
        index.remove(key);
      }
    }
    return scans;
  }

  static Map<K, List<Violation>> _readOnlyView<K>(
    Map<K, List<Violation>> src,
  ) {
    return Map<K, List<Violation>>.unmodifiable(
      src.map(
        (k, vs) => MapEntry(k, List<Violation>.unmodifiable(vs)),
      ),
    );
  }

  /// Translates a simple glob (`*`, `**`, `?`) into a [RegExp], using
  /// the same minimal vocabulary the project file uses for file
  /// includes. `*` matches one path segment, `**` matches any number of
  /// path segments including zero, `?` matches any single character.
  ///
  /// We deliberately don't pull in the full `package:glob` matcher here:
  /// it works over filesystem entities, not raw strings, and the filter
  /// surface only ever needs string matching. A targeted [RegExp] keeps
  /// the store free of platform I/O.
  static RegExp _glob(String pattern) {
    final buf = StringBuffer('^');
    var i = 0;
    while (i < pattern.length) {
      final c = pattern[i];
      if (c == '*') {
        if (i + 1 < pattern.length && pattern[i + 1] == '*') {
          buf.write('.*');
          i += 2;
          continue;
        }
        buf.write('[^/]*');
      } else if (c == '?') {
        buf.write('[^/]');
      } else if (r'\^$.|+()[]{}'.contains(c)) {
        buf
          ..write(r'\')
          ..write(c);
      } else {
        buf.write(c);
      }
      i++;
    }
    buf.write(r'$');
    return RegExp(buf.toString());
  }
}
