// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:meta/meta.dart';

/// One row in the violation trend store — a single violation
/// captured at a single moment in time.
///
/// Trend tracking (Pro tier) records every violation from every completed lint
/// run into the store, then drives the per-rule / severity-drift / project /
/// heatmap chart screens off the resulting history.
///
/// The data point intentionally carries the message (so the chart's
/// tooltip can disambiguate two violations with the same rule on the
/// same file) but drops the column number — line is sufficient
/// granularity for trend analysis and dropping column compresses
/// storage.
@immutable
class ViolationTrendDataPoint {
  /// Creates a [ViolationTrendDataPoint].
  const ViolationTrendDataPoint({
    required this.runId,
    required this.runTimestamp,
    required this.ruleId,
    required this.severity,
    required this.filePath,
    required this.message,
    this.lineNumber,
  });

  /// Stable identifier of the lint run this point belongs to.
  final String runId;

  /// UTC timestamp the run completed at — drives time-axis sorting,
  /// bucketing, and retention pruning.
  final DateTime runTimestamp;

  /// Engine-namespaced rule id, e.g. `verilator/UNUSEDSIGNAL`.
  final String ruleId;

  /// Severity of the violation.
  final Severity severity;

  /// File path the violation was reported against. Relative to the
  /// project root when possible; absolute otherwise.
  final String filePath;

  /// Line number (1-based) when known, `null` for file-level
  /// violations.
  final int? lineNumber;

  /// Engine-emitted message. Carried so the per-rule chart tooltip
  /// can disambiguate duplicate violations on the same line.
  final String message;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ViolationTrendDataPoint) return false;
    return runId == other.runId &&
        runTimestamp == other.runTimestamp &&
        ruleId == other.ruleId &&
        severity == other.severity &&
        filePath == other.filePath &&
        lineNumber == other.lineNumber &&
        message == other.message;
  }

  @override
  int get hashCode => Object.hash(
    runId,
    runTimestamp,
    ruleId,
    severity,
    filePath,
    lineNumber,
    message,
  );

  @override
  String toString() =>
      'ViolationTrendDataPoint('
      'runId: $runId, ruleId: $ruleId, severity: ${severity.name})';
}
