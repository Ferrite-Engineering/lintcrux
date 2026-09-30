// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A persistent rule waiver — Pro-tier feature.
///
/// The open core ships the model so the [Violation] type can declare
/// `suppression: Waiver?`; the managed waiver store, matching engine and UI
/// live in the Pro overlay. Maps onto SARIF's `result.suppressions[]` entry
/// (SARIF §3.34) — `id` mirrors `suppression.guid`, `reason` mirrors
/// `justification`, `author` / `createdAt` / `expiresAt` mirror `properties`
/// bag fields.
///
/// Match scope in the model is deliberately small: a waiver matches a
/// concrete `(ruleId, filePath)` pair plus an optional line range.
/// Globbing, severity-aware matching and module-scope waivers belong to
/// the matcher, not the model.
@immutable
class Waiver {
  /// Creates a [Waiver]. `id` is a stable identifier (typically a UUID
  /// or a hash of the matcher) — used for waiver audit trails and as a
  /// React-style stable key in the UI.
  const Waiver({
    required this.id,
    required this.ruleId,
    required this.filePath,
    required this.reason,
    required this.author,
    required this.createdAt,
    this.lineStart,
    this.lineEnd,
    this.expiresAt,
  });

  /// Stable opaque identifier (UUID v4 by default).
  final String id;

  /// Engine-namespaced rule this waiver suppresses
  /// (e.g. `"verilator/UNUSEDSIGNAL"`).
  final String ruleId;

  /// Absolute path to the source file the waiver applies to.
  final String filePath;

  /// Inclusive 1-based start line of the waiver range. `null` waives
  /// every occurrence in the file.
  final int? lineStart;

  /// Inclusive 1-based end line. Required when `lineStart` is set.
  final int? lineEnd;

  /// Human-readable justification. Surfaced in the inspector and in
  /// audit reports — non-empty is enforced at the UI layer.
  final String reason;

  /// Author identity (typically the OS-user name or, in Enterprise, an
  /// SSO-resolved identifier).
  final String author;

  /// When the waiver was first persisted. Used for audit and for
  /// "waivers older than N" reports.
  final DateTime createdAt;

  /// Optional expiration. Past this date, the waiver no longer matches
  /// and the underlying violation reappears in the table.
  final DateTime? expiresAt;

  /// Returns a copy with overridden fields.
  Waiver copyWith({
    String? id,
    String? ruleId,
    String? filePath,
    int? lineStart,
    int? lineEnd,
    String? reason,
    String? author,
    DateTime? createdAt,
    DateTime? expiresAt,
  }) {
    return Waiver(
      id: id ?? this.id,
      ruleId: ruleId ?? this.ruleId,
      filePath: filePath ?? this.filePath,
      lineStart: lineStart ?? this.lineStart,
      lineEnd: lineEnd ?? this.lineEnd,
      reason: reason ?? this.reason,
      author: author ?? this.author,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Waiver &&
        other.id == id &&
        other.ruleId == ruleId &&
        other.filePath == filePath &&
        other.lineStart == lineStart &&
        other.lineEnd == lineEnd &&
        other.reason == reason &&
        other.author == author &&
        other.createdAt == createdAt &&
        other.expiresAt == expiresAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    ruleId,
    filePath,
    lineStart,
    lineEnd,
    reason,
    author,
    createdAt,
    expiresAt,
  );

  @override
  String toString() => 'Waiver($id, $ruleId, $filePath, by $author)';
}
