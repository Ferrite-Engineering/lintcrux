// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// What happened to the active baseline.
enum BaselineAuditAction { set, cleared }

/// A single audit-log entry emitted by a [BaselineStore] on every
/// `setBaseline` / `clearBaseline` call.
///
/// Mirrors the shape of the waiver audit-trail's `WaiverAuditEntry`:
/// JSON-lines friendly, timestamps in UTC ISO 8601, and a
/// previous-id field so the history is reconstructible from append-
/// only logs alone.
@immutable
class BaselineAuditEntry {
  /// Creates a [BaselineAuditEntry].
  const BaselineAuditEntry({
    required this.timestamp,
    required this.action,
    required this.projectPath,
    this.baselineId,
    this.previousBaselineId,
    this.frozenCount,
    this.author,
  });

  /// When the mutation happened (UTC on disk).
  final DateTime timestamp;

  /// Mutation kind.
  final BaselineAuditAction action;

  /// Absolute project path the mutation was scoped to.
  final String projectPath;

  /// Id of the **new** active baseline after a `set`. `null` for
  /// `cleared` entries.
  final String? baselineId;

  /// Id of the baseline that was replaced (or cleared). `null` when
  /// `set` runs against an empty store (first baseline ever).
  final String? previousBaselineId;

  /// Number of frozen violations in the newly-set baseline. `null`
  /// for `cleared` entries.
  final int? frozenCount;

  /// Author tag, when known. Same shape as the waiver audit's
  /// `author` field.
  final String? author;

  /// JSON-serializable view of the entry. One line per entry when
  /// the file-backed sink writes JSON-lines.
  Map<String, Object?> toJson() => <String, Object?>{
    'timestamp': timestamp.toUtc().toIso8601String(),
    'action': action.name,
    'projectPath': projectPath,
    if (baselineId != null) 'baselineId': baselineId,
    if (previousBaselineId != null) 'previousBaselineId': previousBaselineId,
    if (frozenCount != null) 'frozenCount': frozenCount,
    if (author != null) 'author': author,
  };
}

/// Audit-trail sink for baseline mutations.
///
/// The Pro overlay's file-based default appends
/// JSON-lines records to `<project-root>/.lintcrux-baseline.audit.jsonl`.
/// The Enterprise tier swaps in a `crux_audit`-backed sink with
/// the same interface — the [BaselineStore] implementation never
/// knows which backend is active.
abstract class BaselineAuditSink {
  /// Records [entry]. Implementations are best-effort: a failure
  /// must never block the underlying mutation, because the persisted
  /// baseline is the system of record.
  Future<void> record(BaselineAuditEntry entry);
}

/// No-op sink: the default of a store constructed without an audit trail,
/// and what a caller passes to disable audit logging entirely.
class NoopBaselineAuditSink implements BaselineAuditSink {
  /// Const constructor.
  const NoopBaselineAuditSink();

  @override
  Future<void> record(BaselineAuditEntry entry) async {}
}
