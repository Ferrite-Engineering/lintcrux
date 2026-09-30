// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/models/baseline_violation.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:meta/meta.dart';

/// Pro-tier bookmark of a specific violation for follow-up.
///
/// A [BookmarkedViolation] flags a single violation the engineer wants
/// to revisit (TODO, "ask Bob about this", "fix in v2.1"). Bookmarks
/// persist across lint runs by reusing the same stable [fingerprint]
/// scheme as [BaselineViolation], so a bookmark survives line-shifts
/// caused by surrounding edits and even survives temporary runs where
/// the violation does not fire (the bookmark is then flagged "stale"
/// via [lastSeenRunId]).
///
/// The model carries:
///   - [fingerprint] — the matching key (computed via
///     [BaselineFingerprint.forProject], identical to the baseline
///     fingerprint, so root-relative)
///   - [ruleId] / [filePath] / [lineNumber] / [snippet] — recorded for
///     display when the violation is not currently firing
///   - [note] — optional markdown user note
///   - [color] — optional color tag for visual grouping
///   - [lastSeenRunId] — id of the most recent run where the
///     violation fired; `null` if the bookmark has never been re-seen
///     since creation. Stale-detection uses this field.
///
/// Persistence shape mirrors [LintBaseline]: schema [version] is
/// required, unknown versions are rejected with [FormatException], and
/// the on-disk JSON is round-trippable via [toJson] / [fromJson].
///
/// Version 1 fingerprints hashed the absolute file path; version 2
/// fingerprints are project-root-relative, like baselines. [fromJson]
/// still reads version 1 and keeps its [version], and the store that
/// knows the project root upgrades it with [withProjectFingerprint].
@immutable
class BookmarkedViolation {
  /// Creates a [BookmarkedViolation].
  const BookmarkedViolation({
    required this.id,
    required this.fingerprint,
    required this.ruleId,
    required this.filePath,
    required this.lineNumber,
    required this.snippet,
    required this.createdAt,
    required this.updatedAt,
    this.note,
    this.color,
    this.lastSeenRunId,
    this.version = currentVersion,
  });

  /// Computes a [BookmarkedViolation] for a live [Violation] at the
  /// moment of bookmark creation. The fingerprint matches the
  /// baseline fingerprint scheme so a violation cannot have two
  /// "identities" depending on whether it is being bookmarked or
  /// baselined.
  ///
  /// [projectRoot] is the open project's `LintProject.rootPath`.
  factory BookmarkedViolation.fromViolation({
    required String id,
    required Violation violation,
    required DateTime createdAt,
    required String projectRoot,
    String? note,
    String? color,
    String? lastSeenRunId,
  }) {
    return BookmarkedViolation(
      id: id,
      fingerprint: BaselineFingerprint.forProject(
        ruleId: violation.ruleId,
        filePath: violation.location.file,
        message: violation.message,
        projectRoot: projectRoot,
      ),
      ruleId: violation.ruleId,
      filePath: violation.location.file,
      lineNumber: violation.location.line,
      snippet: violation.message,
      createdAt: createdAt,
      updatedAt: createdAt,
      note: note,
      color: color,
      lastSeenRunId: lastSeenRunId,
    );
  }

  /// Parses [json]. Throws [FormatException] for missing required
  /// fields, wrong-type fields, or an unrecognized `version`.
  factory BookmarkedViolation.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! int) {
      throw const FormatException(
        "BookmarkedViolation missing required 'version' field",
      );
    }
    if (version != currentVersion && version != absolutePathVersion) {
      throw FormatException(
        'Unsupported bookmark schema version: $version '
        '(this build understands v$absolutePathVersion and '
        'v$currentVersion)',
      );
    }
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException(
        "BookmarkedViolation missing required 'id' field",
      );
    }
    final fingerprint = json['fingerprint'];
    if (fingerprint is! String || fingerprint.isEmpty) {
      throw const FormatException(
        "BookmarkedViolation missing required 'fingerprint' field",
      );
    }
    final ruleId = json['ruleId'];
    if (ruleId is! String || ruleId.isEmpty) {
      throw const FormatException(
        "BookmarkedViolation missing required 'ruleId' field",
      );
    }
    final filePath = json['filePath'];
    if (filePath is! String || filePath.isEmpty) {
      throw const FormatException(
        "BookmarkedViolation missing required 'filePath' field",
      );
    }
    final lineNumber = json['lineNumber'];
    if (lineNumber is! int || lineNumber < 1) {
      throw const FormatException(
        "BookmarkedViolation 'lineNumber' field must be a positive integer",
      );
    }
    final snippet = json['snippet'];
    if (snippet is! String) {
      throw const FormatException(
        "BookmarkedViolation 'snippet' field must be a string",
      );
    }
    final createdAtRaw = json['createdAt'];
    if (createdAtRaw is! String) {
      throw const FormatException(
        "BookmarkedViolation 'createdAt' field must be an ISO 8601 string",
      );
    }
    final updatedAtRaw = json['updatedAt'];
    if (updatedAtRaw is! String) {
      throw const FormatException(
        "BookmarkedViolation 'updatedAt' field must be an ISO 8601 string",
      );
    }
    final noteRaw = json['note'];
    final colorRaw = json['color'];
    final lastSeenRunIdRaw = json['lastSeenRunId'];
    return BookmarkedViolation(
      id: id,
      fingerprint: fingerprint,
      ruleId: ruleId,
      filePath: filePath,
      lineNumber: lineNumber,
      snippet: snippet,
      createdAt: DateTime.parse(createdAtRaw),
      updatedAt: DateTime.parse(updatedAtRaw),
      note: noteRaw is String && noteRaw.isNotEmpty ? noteRaw : null,
      color: colorRaw is String && colorRaw.isNotEmpty ? colorRaw : null,
      lastSeenRunId: lastSeenRunIdRaw is String && lastSeenRunIdRaw.isNotEmpty
          ? lastSeenRunIdRaw
          : null,
      version: version,
    );
  }

  /// Current schema version. Bumped whenever the on-disk JSON
  /// representation changes in a backward-incompatible way.
  static const int currentVersion = 2;

  /// The schema whose [fingerprint] hashed the absolute file path. Read,
  /// and upgraded with [withProjectFingerprint].
  static const int absolutePathVersion = 1;

  /// Stable identifier (UUID). Used as the bookmark-list key and as
  /// the lookup token when the user toggles a bookmark off.
  final String id;

  /// Stable hash of `(ruleId, root-relative filePath, normalized-snippet)`.
  /// Identical to the baseline fingerprint scheme so bookmarks and
  /// baselines agree on violation identity. See
  /// [BaselineFingerprint.forProject].
  final String fingerprint;

  /// Engine-namespaced rule id, e.g. `verilator/UNUSEDSIGNAL`. Preserved
  /// for filtering in the bookmark panel even when the violation no
  /// longer fires.
  final String ruleId;

  /// Absolute path to the source file at bookmark time. Used for
  /// display and for the "jump to violation" action.
  final String filePath;

  /// 1-based line number at bookmark time. Recorded for display —
  /// line shifts are tolerated by the fingerprint match, so a stale
  /// bookmark might point at a different line than the live violation
  /// (the live violation's location wins for navigation).
  final int lineNumber;

  /// Short capture of the violation message at bookmark time. Shown in
  /// the bookmark panel for context when the violation no longer fires.
  final String snippet;

  /// Optional markdown user note attached to the bookmark.
  final String? note;

  /// Optional color tag for visual grouping in the bookmark panel.
  /// Stored as a CSS hex string (`#RRGGBB`); the renderer parses it
  /// and falls back to a default color on malformed input.
  final String? color;

  /// Id of the most recent run where the violation fired. `null` until
  /// the first run after bookmark creation. The bookmark store's
  /// stale-detection hook updates this on every project-wide
  /// [LintRunCompletionEvent].
  final String? lastSeenRunId;

  /// Creation timestamp (UTC).
  final DateTime createdAt;

  /// Last-modified timestamp (UTC). Updated on note / color edits;
  /// **not** updated on stale-detection updates (those touch
  /// [lastSeenRunId] only).
  final DateTime updatedAt;

  /// Schema version. Always [currentVersion] on freshly constructed
  /// instances; preserved during [copyWith].
  final int version;

  /// This bookmark with a root-relative [fingerprint] at [currentVersion].
  ///
  /// A [currentVersion] bookmark is returned unchanged. A version 1
  /// bookmark's fingerprint is recomputed from its stored rule, absolute
  /// file and snippet — the snippet is the violation message the old
  /// fingerprint hashed — so the upgrade is exact.
  BookmarkedViolation withProjectFingerprint(String projectRoot) {
    if (version == currentVersion) return this;
    return BookmarkedViolation(
      id: id,
      fingerprint: BaselineFingerprint.forProject(
        ruleId: ruleId,
        filePath: filePath,
        message: snippet,
        projectRoot: projectRoot,
      ),
      ruleId: ruleId,
      filePath: filePath,
      lineNumber: lineNumber,
      snippet: snippet,
      createdAt: createdAt,
      updatedAt: updatedAt,
      note: note,
      color: color,
      lastSeenRunId: lastSeenRunId,
    );
  }

  /// Returns a copy with overridden fields.
  BookmarkedViolation copyWith({
    String? id,
    String? fingerprint,
    String? ruleId,
    String? filePath,
    int? lineNumber,
    String? snippet,
    String? note,
    String? color,
    String? lastSeenRunId,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearNote = false,
    bool clearColor = false,
    bool clearLastSeenRunId = false,
  }) {
    return BookmarkedViolation(
      id: id ?? this.id,
      fingerprint: fingerprint ?? this.fingerprint,
      ruleId: ruleId ?? this.ruleId,
      filePath: filePath ?? this.filePath,
      lineNumber: lineNumber ?? this.lineNumber,
      snippet: snippet ?? this.snippet,
      note: clearNote ? null : (note ?? this.note),
      color: clearColor ? null : (color ?? this.color),
      lastSeenRunId: clearLastSeenRunId
          ? null
          : (lastSeenRunId ?? this.lastSeenRunId),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version,
    );
  }

  /// Round-trippable JSON view. Key order is deterministic so
  /// committed JSON files diff cleanly.
  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'id': id,
    'fingerprint': fingerprint,
    'ruleId': ruleId,
    'filePath': filePath,
    'lineNumber': lineNumber,
    'snippet': snippet,
    if (note != null) 'note': note,
    if (color != null) 'color': color,
    if (lastSeenRunId != null) 'lastSeenRunId': lastSeenRunId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! BookmarkedViolation) return false;
    return other.id == id &&
        other.fingerprint == fingerprint &&
        other.ruleId == ruleId &&
        other.filePath == filePath &&
        other.lineNumber == lineNumber &&
        other.snippet == snippet &&
        other.note == note &&
        other.color == color &&
        other.lastSeenRunId == lastSeenRunId &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.version == version;
  }

  @override
  int get hashCode => Object.hash(
    id,
    fingerprint,
    ruleId,
    filePath,
    lineNumber,
    snippet,
    note,
    color,
    lastSeenRunId,
    createdAt,
    updatedAt,
    version,
  );

  @override
  String toString() =>
      'BookmarkedViolation($id, $ruleId, '
      '$filePath:$lineNumber, fp=$fingerprint)';
}
