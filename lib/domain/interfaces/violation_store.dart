// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/violation.dart';

/// The unified, in-memory violation set, derived from the most recent
/// run of every active engine.
///
/// The store is the single source of truth that the violation table,
/// the inspector, the status bar summary, and the export pipeline all
/// consume. Implementations maintain pre-computed indices ([bySeverity],
/// [byEngine], …) so interactive filtering stays sub-millisecond on
/// 50,000-row sets.
///
/// The indexed in-memory implementation is `InMemoryViolationStore`.
abstract class ViolationStore {
  /// Replace the violations from a specific engine with a new set
  /// (called when a run completes). Existing violations from *other*
  /// engines are untouched.
  void replaceFromEngine(String engineId, List<Violation> violations);

  /// Replace only the [engineId] violations whose
  /// `location.file` matches an entry in [changedFiles] with
  /// [newViolations]. Existing engine violations on files outside
  /// [changedFiles] are preserved; violations from *other* engines are
  /// untouched.
  ///
  /// This is the incremental-re-run path: when the file watcher fires
  /// for a single source file, an engine that declares
  /// `supportsIncrementalPerFile` re-lints only that file and calls
  /// this method with the new file's violations. The rest of the
  /// engine's per-file violations stay in place so the user does not
  /// see them flash out and back in.
  ///
  /// Implementations must keep every index ([bySeverity], [byEngine],
  /// [byRule], [byFile]) consistent with the surviving + new set.
  /// Engine-id consistency is asserted in debug builds — every
  /// violation in [newViolations] must have `engineId == engineId`.
  void replacePartialFromEngine(
    String engineId,
    Set<String> changedFiles,
    List<Violation> newViolations,
  );

  /// Add a single violation as it streams in from an in-progress run.
  /// Implementations should debounce index updates so a burst of
  /// `addStreaming` calls doesn't pessimize the UI.
  void addStreaming(Violation v);

  /// Mark the streaming run for [engineId] complete. Implementations
  /// flush any pending index updates and emit a
  /// [ViolationStoreEvent.runCompleted] event.
  void completeStreaming(String engineId);

  /// All currently-known violations across all engines.
  ///
  /// This materializes an unmodifiable copy of the whole set — O(N). When you
  /// only need the size or emptiness, use [count] / [isEmpty]; when you only
  /// need one engine's violations, use [byEngineOf] — none of which copy the
  /// whole store.
  List<Violation> get all;

  /// Total number of violations across all engines, in O(1) — without
  /// materializing [all].
  int get count;

  /// Whether the store holds no violations, in O(1) — without materializing
  /// [all].
  bool get isEmpty;

  /// The violations for a single [engineId], as an unmodifiable view — O(1),
  /// without copying the other engines' buckets the way reading [byEngine]
  /// (and then indexing) does. Empty when the engine has no violations.
  List<Violation> byEngineOf(String engineId);

  /// Pre-computed index by severity. Values are unmodifiable.
  Map<Severity, List<Violation>> get bySeverity;

  /// Pre-computed index by engine ID. Values are unmodifiable.
  Map<String, List<Violation>> get byEngine;

  /// Pre-computed index by engine-namespaced rule ID. Values are
  /// unmodifiable.
  Map<String, List<Violation>> get byRule;

  /// Pre-computed index by absolute file path. Values are
  /// unmodifiable.
  Map<String, List<Violation>> get byFile;

  /// Apply [filter] and return the matching subset.
  List<Violation> filter(ViolationFilter filter);

  /// Stream of changes for reactive UI consumption. Emits an event
  /// every time the underlying set changes (replace / stream-add /
  /// stream-complete / waiver-mutation).
  Stream<ViolationStoreEvent> get events;
}

/// Filter spec applied by [ViolationStore.filter].
///
/// All fields are AND-combined; within a field, multiple values are
/// OR-combined. `null` / empty means "don't filter on this dimension".
class ViolationFilter {
  /// Creates a [ViolationFilter].
  const ViolationFilter({
    this.severities,
    this.engineIds,
    this.ruleSubstring,
    this.fileGlob,
    this.includeSuppressed = false,
  });

  /// Empty filter — matches every violation.
  static const empty = ViolationFilter();

  /// Restrict to these severities. `null` == any.
  final Set<Severity>? severities;

  /// Restrict to these engines. `null` == any.
  final Set<String>? engineIds;

  /// Case-insensitive substring match against rule ID and message.
  /// `null` or empty == any.
  final String? ruleSubstring;

  /// Glob match against the source file path. `null` or empty == any.
  final String? fileGlob;

  /// When `false` (default), violations with a non-null suppression
  /// are excluded. When `true`, they are included (with the
  /// suppression rendered in the UI).
  final bool includeSuppressed;
}

/// Change notification for [ViolationStore.events].
sealed class ViolationStoreEvent {
  const ViolationStoreEvent();
}

/// An engine's violation set was wholesale replaced.
class EngineReplaced extends ViolationStoreEvent {
  /// Creates an [EngineReplaced] event.
  const EngineReplaced(this.engineId, this.violationCount);

  /// Engine whose set was replaced.
  final String engineId;

  /// New count after replacement.
  final int violationCount;
}

/// A single violation streamed in.
class ViolationAdded extends ViolationStoreEvent {
  /// Creates a [ViolationAdded] event.
  const ViolationAdded(this.violation);

  /// The newly-added violation.
  final Violation violation;
}

/// An engine's streaming run completed.
class RunCompleted extends ViolationStoreEvent {
  /// Creates a [RunCompleted] event.
  const RunCompleted(this.engineId);

  /// Engine whose run completed.
  final String engineId;
}
