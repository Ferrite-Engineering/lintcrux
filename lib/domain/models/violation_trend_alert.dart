// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:meta/meta.dart';

/// Severity tier of a [ViolationTrendAlert].
///
/// Drives the alert banner's color and badge icon.
enum ViolationTrendAlertSeverity {
  /// Informational signal — surfaced but does not draw attention.
  info,

  /// Notable signal — colored amber.
  warning,

  /// Severe signal — colored red and pinned to the top of the alerts
  /// banner.
  critical,
}

/// Detection kind for a [ViolationTrendAlert].
enum ViolationTrendAlertKind {
  /// Per-severity violation count drifted upward by more than the
  /// configured threshold percentage over the last N runs vs. the
  /// prior M runs.
  severityClassDrift,

  /// A rule that didn't fire in the prior M runs has now fired in
  /// each of the last N consecutive runs.
  newPersistentRule,

  /// A single run's violation count for a specific rule exceeded a
  /// multiple of the rolling-window mean (e.g. 3x).
  suddenSpike,
}

/// A trend-anomaly alert produced by the Pro
/// `ViolationTrendAlertDetector` analyzing recent
/// [ViolationTrendDataPoint]s.
///
/// Surfaced in the Pro dashboard banner and in the per-rule chart's
/// summary bar.
@immutable
class ViolationTrendAlert {
  /// Creates a [ViolationTrendAlert].
  const ViolationTrendAlert({
    required this.alertKind,
    required this.alertSeverity,
    required this.baselineValue,
    required this.currentValue,
    required this.deltaPercent,
    required this.detectedAtRunId,
    this.ruleId,
    this.severity,
    this.firstObservedAtRunId,
  });

  /// Which detection rule produced this alert.
  final ViolationTrendAlertKind alertKind;

  /// Display severity for the alert banner.
  final ViolationTrendAlertSeverity alertSeverity;

  /// Rule id this alert is scoped to (for [newPersistentRule] and
  /// [suddenSpike]). `null` for severity-class drift alerts that
  /// span the whole project.
  final String? ruleId;

  /// Violation [Severity] this alert is scoped to (for
  /// [severityClassDrift]). `null` for other kinds.
  final Severity? severity;

  /// Baseline value the current value is compared against.
  ///
  /// For [severityClassDrift]: prior-window mean count.
  /// For [newPersistentRule]: prior consecutive-run firing count
  /// (typically zero, by definition of "new persistent rule").
  /// For [suddenSpike]: rolling-window mean count.
  final double baselineValue;

  /// Current observed value.
  ///
  /// For [severityClassDrift]: recent-window mean count.
  /// For [newPersistentRule]: current consecutive-run firing count.
  /// For [suddenSpike]: current run's count for the rule.
  final double currentValue;

  /// `(currentValue - baselineValue) / baselineValue * 100`. May
  /// equal `double.infinity` when `baselineValue` is zero (e.g.
  /// [newPersistentRule] alerts).
  final double deltaPercent;

  /// Run id where the detector first noticed the anomaly.
  final String detectedAtRunId;

  /// First run id where the underlying condition appeared. May be
  /// equal to [detectedAtRunId] for single-run spikes; may be
  /// earlier for multi-run conditions like [newPersistentRule]. `null`
  /// when the detector cannot reconstruct the origin.
  final String? firstObservedAtRunId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ViolationTrendAlert) return false;
    return alertKind == other.alertKind &&
        alertSeverity == other.alertSeverity &&
        ruleId == other.ruleId &&
        severity == other.severity &&
        baselineValue == other.baselineValue &&
        currentValue == other.currentValue &&
        deltaPercent == other.deltaPercent &&
        detectedAtRunId == other.detectedAtRunId &&
        firstObservedAtRunId == other.firstObservedAtRunId;
  }

  @override
  int get hashCode => Object.hash(
    alertKind,
    alertSeverity,
    ruleId,
    severity,
    baselineValue,
    currentValue,
    deltaPercent,
    detectedAtRunId,
    firstObservedAtRunId,
  );

  @override
  String toString() =>
      'ViolationTrendAlert('
      'kind: $alertKind, severity: $alertSeverity, '
      'ruleId: $ruleId, deltaPercent: $deltaPercent)';
}
