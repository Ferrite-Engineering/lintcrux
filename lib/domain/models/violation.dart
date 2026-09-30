// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/waiver.dart';
import 'package:meta/meta.dart';

/// The central unified violation record.
///
/// One [Violation] corresponds to one entry in SARIF's
/// `runs[*].results[*]` — see SARIF 2.1.0 §3.27. The shape here is an
/// ergonomic Dart wrapper that the in-memory store and UI consume
/// directly; round-trips to SARIF happen at the serialization
/// boundary (`SarifReport`).
///
/// The `engineId` / `ruleId` pair must be consistent: `ruleId` is
/// engine-namespaced (`"<engineId>/<localRuleId>"`) so the violation
/// table can sort, filter, and link to the rule database without
/// engine-aware logic.
///
/// `raw` preserves the underlying SARIF result object as a `Map` so
/// engine-specific data we don't surface in the Dart wrapper (vendor
/// `properties` bags, fix suggestions, related taxa) survives a
/// load → export round-trip. It is empty for hand-constructed
/// violations.
@immutable
class Violation {
  /// Creates a [Violation].
  const Violation({
    required this.engineId,
    required this.ruleId,
    required this.severity,
    required this.message,
    required this.location,
    this.relatedLocations = const <SourceLocation>[],
    this.suppression,
    this.raw = const <String, dynamic>{},
  });

  /// Stable engine identifier — matches `LintEngine.id`
  /// (e.g. `"verilator"`, `"verible"`).
  final String engineId;

  /// Engine-namespaced rule identifier
  /// (e.g. `"verilator/UNUSEDSIGNAL"`).
  final String ruleId;

  /// Severity *as decided for this occurrence* — may differ from the
  /// rule's default if the project applies a per-rule severity
  /// override.
  final Severity severity;

  /// The engine's message text, copied verbatim (with the
  /// engine-specific severity prefix and `<rule>:` token stripped during
  /// parsing).
  final String message;

  /// Primary source location.
  final SourceLocation location;

  /// Additional locations the engine reports as related — e.g. the
  /// declaration site for an unused signal, the driver site for a
  /// multi-driven net. Surfaced in the inspector with click-to-navigate.
  final List<SourceLocation> relatedLocations;

  /// The matching waiver, or `null` if no waiver suppresses this
  /// occurrence. Set by the open-core inline-pragma transformer, by the
  /// Pro managed-waiver matcher, and by `SarifReader` for a result read
  /// with an accepted `suppressions` entry.
  final Waiver? suppression;

  /// Whether this violation is currently suppressed by [suppression].
  bool get isSuppressed => suppression != null;

  /// The underlying SARIF `result` object preserved verbatim for
  /// round-tripping. Untyped by design — SARIF's full shape is too wide
  /// for a typed mirror.
  final Map<String, dynamic> raw;

  /// Returns a copy with overridden fields. Pass an explicit `null`
  /// `suppression` via [clearSuppression] to remove a waiver — the
  /// `Waiver? suppression` parameter's `null` literal means "don't
  /// touch", per the standard `copyWith` convention.
  Violation copyWith({
    String? engineId,
    String? ruleId,
    Severity? severity,
    String? message,
    SourceLocation? location,
    List<SourceLocation>? relatedLocations,
    Waiver? suppression,
    Map<String, dynamic>? raw,
    bool clearSuppression = false,
  }) {
    return Violation(
      engineId: engineId ?? this.engineId,
      ruleId: ruleId ?? this.ruleId,
      severity: severity ?? this.severity,
      message: message ?? this.message,
      location: location ?? this.location,
      relatedLocations: relatedLocations ?? this.relatedLocations,
      suppression: clearSuppression ? null : (suppression ?? this.suppression),
      raw: raw ?? this.raw,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Violation) return false;
    if (other.engineId != engineId) return false;
    if (other.ruleId != ruleId) return false;
    if (other.severity != severity) return false;
    if (other.message != message) return false;
    if (other.location != location) return false;
    if (other.suppression != suppression) return false;
    if (other.relatedLocations.length != relatedLocations.length) return false;
    for (var i = 0; i < relatedLocations.length; i++) {
      if (other.relatedLocations[i] != relatedLocations[i]) return false;
    }
    // `raw` is excluded from equality intentionally — two semantically
    // equal violations should compare equal even if their preserved
    // SARIF blobs have different ordering / non-essential metadata.
    return true;
  }

  @override
  int get hashCode => Object.hash(
    engineId,
    ruleId,
    severity,
    message,
    location,
    suppression,
    Object.hashAll(relatedLocations),
  );

  @override
  String toString() =>
      'Violation($engineId, $ruleId, $severity, $location'
      '${isSuppressed ? ', suppressed' : ''})';
}
