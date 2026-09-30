// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/models/baseline_delta.dart';
import 'package:lintcrux/domain/models/baseline_violation.dart';
import 'package:lintcrux/domain/models/lint_baseline.dart';
import 'package:lintcrux/domain/models/violation.dart';

/// Pure-function classifier that compares a live run's violations
/// against a [LintBaseline] and produces a [BaselineDelta].
///
/// This is the engine of the "Baseline & delta" workflow.
/// The filter does not own any I/O — the [BaselineStore] handles
/// persistence; the run pipeline calls [classify] after the
/// transformer chain has run so suppressions and severity overrides
/// already reflect the user's intent. Keeping this pure makes it
/// trivially unit-testable without the Pro overlay.
///
/// Matching uses [BaselineViolation.fingerprint], which deliberately
/// excludes the line number — a violation that shifts down by a few
/// lines because a preceding `import` was added still counts as the
/// same defect. See [BaselineFingerprint] for the exact algorithm.
class BaselineFilter {
  const BaselineFilter._();

  /// Classifies [current] against [baseline]. When `baseline` is
  /// `null`, every current violation is reported as `new` (the
  /// "no baseline set" branch — the user has not yet snapshotted, so
  /// every violation is implicitly post-baseline).
  ///
  /// [projectRoot] is the root of the project [current] came from — the
  /// run's own root, not [LintBaseline.projectPath]. Fingerprints are
  /// root-relative, so a baseline set in one checkout classifies a run
  /// in another.
  static BaselineDelta classify({
    required List<Violation> current,
    required LintBaseline? baseline,
    required String projectRoot,
  }) {
    if (baseline == null) {
      return BaselineDelta(
        newViolations: List<Violation>.unmodifiable(current),
        persistingViolations: const <Violation>[],
        resolvedViolations: const <BaselineViolation>[],
      );
    }
    final baselineFingerprints = baseline.fingerprintSet;
    // Track which baseline fingerprints we've matched so the
    // "resolved" list is `baseline - matched`. We don't mutate the
    // baseline's `frozenViolations` list — that would violate the
    // immutability contract — but we do build a working set of the
    // unmatched fingerprints.
    final unmatched = Set<String>.from(baselineFingerprints);
    final newViolations = <Violation>[];
    final persisting = <Violation>[];
    for (final v in current) {
      // Memoized per instance: classifying a run primes the cache so the
      // "Only new" derive (violation_table_provider) is warm even on its
      // first pass over the same violations.
      final fp = baselineFingerprintFor(v, projectRoot: projectRoot);
      if (baselineFingerprints.contains(fp)) {
        persisting.add(v);
        unmatched.remove(fp);
      } else {
        newViolations.add(v);
      }
    }
    // Build the resolved list in baseline order so the audit / diff
    // view shows deterministic ordering rather than set-iteration
    // order.
    final resolved = <BaselineViolation>[
      for (final bv in baseline.frozenViolations)
        if (unmatched.contains(bv.fingerprint)) bv,
    ];
    return BaselineDelta(
      newViolations: List<Violation>.unmodifiable(newViolations),
      persistingViolations: List<Violation>.unmodifiable(persisting),
      resolvedViolations: List<BaselineViolation>.unmodifiable(resolved),
    );
  }
}
