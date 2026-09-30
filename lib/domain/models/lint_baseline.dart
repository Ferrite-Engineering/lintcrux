// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/models/baseline_violation.dart';
import 'package:meta/meta.dart';

/// Per-instance memoization for [LintBaseline.fingerprintSet]. Weak on its key
/// (an [Expando]) so it keeps [LintBaseline]'s const constructor and never
/// pins a baseline in memory.
final Expando<Set<String>> _fingerprintSetCache = Expando<Set<String>>(
  'fingerprintSet',
);

/// Snapshot of every active violation at a single point in time.
///
/// A baseline complements managed waivers: instead of waiving each
/// existing violation, the engineer snapshots them all in one
/// operation. Subsequent runs can then surface only the *delta* —
/// violations introduced after the baseline. This is the answer to
/// the "we have 10 000 legacy violations; how do we focus on the new
/// ones?" workflow.
///
/// A project has at most one active baseline at a time. Previous
/// baselines are not retained in the in-memory model — they live in
/// the [BaselineAuditSink]'s audit trail. Replacing the active
/// baseline is the supported workflow ("rebase").
///
/// The schema [version] is the source of forward-compatibility: a
/// reader that sees a `version` it does not understand throws
/// [FormatException] from [LintBaseline.fromJson] rather than silently
/// reinterpreting unknown fields.
///
/// Version history:
///
/// - **1** — fingerprints hashed the absolute file path the engines
///   reported, so a baseline matched only runs from the checkout location
///   it was set in.
/// - **2** — fingerprints are project-root-relative
///   (`BaselineFingerprint.forProject`). A v1 file is migrated on read:
///   every frozen entry stores its rule, absolute file and message, and
///   [projectPath] is the root it was set against, so each fingerprint is
///   recomputed exactly. The next write stores v2. A build that
///   understands only v1 refuses a v2 file loudly rather than matching
///   nothing.
@immutable
class LintBaseline {
  /// Creates a [LintBaseline].
  const LintBaseline({
    required this.baselineId,
    required this.createdAt,
    required this.projectPath,
    required this.frozenViolations,
    this.createdBy,
    this.version = currentVersion,
  });

  /// Parses [json], migrating a v1 document to v2. Throws
  /// [FormatException] for missing required fields, wrong-type fields,
  /// or an unrecognized `version`.
  factory LintBaseline.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! int) {
      throw const FormatException(
        "LintBaseline missing required 'version' field",
      );
    }
    if (version != currentVersion && version != _absolutePathVersion) {
      throw FormatException(
        'Unsupported baseline schema version: $version '
        '(this build understands v$_absolutePathVersion and '
        'v$currentVersion)',
      );
    }
    final baselineId = json['baselineId'];
    if (baselineId is! String || baselineId.isEmpty) {
      throw const FormatException(
        "LintBaseline missing required 'baselineId' field",
      );
    }
    final createdAtRaw = json['createdAt'];
    if (createdAtRaw is! String) {
      throw const FormatException(
        "LintBaseline 'createdAt' field must be an ISO 8601 string",
      );
    }
    final createdAt = DateTime.parse(createdAtRaw);
    final projectPath = json['projectPath'];
    if (projectPath is! String || projectPath.isEmpty) {
      throw const FormatException(
        "LintBaseline missing required 'projectPath' field",
      );
    }
    final createdByRaw = json['createdBy'];
    final createdBy = createdByRaw is String ? createdByRaw : null;
    final frozenRaw = json['frozenViolations'];
    if (frozenRaw is! List) {
      throw const FormatException(
        "LintBaseline 'frozenViolations' field must be a list",
      );
    }
    final migrate = version == _absolutePathVersion;
    final frozen = <BaselineViolation>[
      for (final entry in frozenRaw)
        if (entry is Map<String, dynamic>)
          if (migrate)
            BaselineViolation.fromJson(
              entry,
            ).withProjectFingerprint(projectPath)
          else
            BaselineViolation.fromJson(entry),
    ];
    return LintBaseline(
      baselineId: baselineId,
      createdAt: createdAt,
      createdBy: createdBy,
      projectPath: projectPath,
      frozenViolations: frozen,
    );
  }

  /// Current persisted schema version. Bumping requires a migration
  /// path; the JSON reader rejects unknown versions.
  static const int currentVersion = 2;

  /// The schema whose fingerprints hashed absolute paths. Still read, and
  /// migrated on read.
  static const int _absolutePathVersion = 1;

  /// Stable opaque identifier (UUID v4 by default). Used as the
  /// React-style stable key in the UI and as the audit-trail row key.
  final String baselineId;

  /// Wall-clock timestamp when the baseline was set. Surfaced as a date in
  /// the baseline status chip and used as the natural sort key in the audit
  /// trail.
  final DateTime createdAt;

  /// Author label, when known. Typically the OS-user name (or an
  /// SSO-resolved identifier in Enterprise builds). `null` when the
  /// baseline was set without an author context (e.g. CLI run).
  final String? createdBy;

  /// Absolute path to the project root the baseline was set against. Used
  /// by the [BaselineStore] to scope-key the persisted file, by the UI to
  /// confirm the baseline matches the currently open project, and as the
  /// root a v1 document's fingerprints are recomputed against. Matching a
  /// run does not depend on it: fingerprints are root-relative.
  final String projectPath;

  /// Every violation that was active when the baseline was set, in
  /// the order they were ingested. Order is preserved for stable
  /// diffing in the audit trail but matching uses
  /// [BaselineViolation.fingerprint], so order does not affect the
  /// [BaselineFilter] result.
  final List<BaselineViolation> frozenViolations;

  /// Schema version this baseline was written at.
  final int version;

  /// Returns a copy with overridden fields. Pass an explicit `null`
  /// `createdBy` via [clearCreatedBy] to remove an author tag — the
  /// `String? createdBy` parameter's `null` literal means "don't
  /// touch", per the standard `copyWith` convention.
  LintBaseline copyWith({
    String? baselineId,
    DateTime? createdAt,
    String? createdBy,
    String? projectPath,
    List<BaselineViolation>? frozenViolations,
    int? version,
    bool clearCreatedBy = false,
  }) {
    return LintBaseline(
      baselineId: baselineId ?? this.baselineId,
      createdAt: createdAt ?? this.createdAt,
      createdBy: clearCreatedBy ? null : (createdBy ?? this.createdBy),
      projectPath: projectPath ?? this.projectPath,
      frozenViolations: frozenViolations ?? this.frozenViolations,
      version: version ?? this.version,
    );
  }

  /// Round-trippable JSON view.
  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'baselineId': baselineId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (createdBy != null) 'createdBy': createdBy,
    'projectPath': projectPath,
    'frozenViolations': [
      for (final v in frozenViolations) v.toJson(),
    ],
  };

  /// Number of frozen violations.
  int get frozenCount => frozenViolations.length;

  /// All fingerprints in the baseline, as a set for O(1) lookup.
  ///
  /// Memoized per instance (via [_fingerprintSetCache]) and returned
  /// unmodifiable, so the hot "Only new" derive path — which reads this on
  /// every filter keystroke and store event while a baseline is active — pays
  /// the O(n) build only once per baseline rather than reallocating a fresh
  /// [Set] each call. The cache is an [Expando], so it keeps the const
  /// constructor and never keeps a [LintBaseline] alive.
  Set<String> get fingerprintSet =>
      _fingerprintSetCache[this] ??= Set<String>.unmodifiable(<String>{
        for (final v in frozenViolations) v.fingerprint,
      });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LintBaseline) return false;
    if (other.baselineId != baselineId) return false;
    if (other.createdAt != createdAt) return false;
    if (other.createdBy != createdBy) return false;
    if (other.projectPath != projectPath) return false;
    if (other.version != version) return false;
    if (other.frozenViolations.length != frozenViolations.length) return false;
    for (var i = 0; i < frozenViolations.length; i++) {
      if (other.frozenViolations[i] != frozenViolations[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    baselineId,
    createdAt,
    createdBy,
    projectPath,
    version,
    Object.hashAll(frozenViolations),
  );

  @override
  String toString() =>
      'LintBaseline($baselineId, '
      '${frozenViolations.length} frozen, '
      'createdAt=${createdAt.toIso8601String()})';
}
