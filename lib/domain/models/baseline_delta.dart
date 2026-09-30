// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/models/baseline_violation.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:meta/meta.dart';

/// Result of comparing a live run's violations against a baseline.
///
/// Returned by [BaselineFilter.classify].
///
/// * [newViolations] — violations from the current run whose
///   fingerprint is not present in the baseline. These are the
///   "introduced since baseline" violations that the delta view
///   surfaces. The CLI's `--fail-on-new-violations` exit code is
///   derived from this list's emptiness.
/// * [persistingViolations] — violations from the current run whose
///   fingerprint *is* present in the baseline. These are the
///   "legacy" violations that were known when the baseline was set.
/// * [resolvedViolations] — fingerprints that were in the baseline
///   but no longer have a matching violation in the current run. The
///   carried [BaselineViolation] is the frozen record from when the
///   baseline was set (the engine no longer reports the issue, so the
///   live [Violation] no longer exists).
///
/// All three lists are independent and disjoint. The order of each
/// list mirrors the input order (preserves engine emit order for
/// `newViolations` / `persistingViolations`; preserves baseline order
/// for `resolvedViolations`).
@immutable
class BaselineDelta {
  /// Creates a [BaselineDelta].
  const BaselineDelta({
    required this.newViolations,
    required this.persistingViolations,
    required this.resolvedViolations,
  });

  /// Empty delta — convenience for tests and the "no baseline + no
  /// current run" edge case.
  static const BaselineDelta empty = BaselineDelta(
    newViolations: <Violation>[],
    persistingViolations: <Violation>[],
    resolvedViolations: <BaselineViolation>[],
  );

  /// Violations from the current run that do not match any
  /// fingerprint in the baseline.
  final List<Violation> newViolations;

  /// Violations from the current run that *do* match a fingerprint
  /// in the baseline.
  final List<Violation> persistingViolations;

  /// Baseline entries that no longer have a matching live violation
  /// — they have been resolved between baseline-set and the current
  /// run.
  final List<BaselineViolation> resolvedViolations;

  /// Convenience: does the current run introduce any new violations?
  /// Drives the CLI `--fail-on-new-violations` exit code.
  bool get hasNewViolations => newViolations.isNotEmpty;

  /// Total count, mirrors the sum across the three categories.
  int get totalCurrent => newViolations.length + persistingViolations.length;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! BaselineDelta) return false;
    if (other.newViolations.length != newViolations.length) return false;
    for (var i = 0; i < newViolations.length; i++) {
      if (other.newViolations[i] != newViolations[i]) return false;
    }
    if (other.persistingViolations.length != persistingViolations.length) {
      return false;
    }
    for (var i = 0; i < persistingViolations.length; i++) {
      if (other.persistingViolations[i] != persistingViolations[i]) {
        return false;
      }
    }
    if (other.resolvedViolations.length != resolvedViolations.length) {
      return false;
    }
    for (var i = 0; i < resolvedViolations.length; i++) {
      if (other.resolvedViolations[i] != resolvedViolations[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(newViolations),
    Object.hashAll(persistingViolations),
    Object.hashAll(resolvedViolations),
  );

  @override
  String toString() =>
      'BaselineDelta('
      'new=${newViolations.length}, '
      'persisting=${persistingViolations.length}, '
      'resolved=${resolvedViolations.length})';
}
