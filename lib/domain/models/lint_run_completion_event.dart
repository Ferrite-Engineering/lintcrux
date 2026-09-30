// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/models/violation_trend_data_point.dart';
import 'package:meta/meta.dart';

/// Cross-cutting event fired when a complete lint run finishes — i.e.
/// every engine has reported its terminal status and the violation
/// store is consistent for the run.
///
/// Consumed by the trend store to ingest one
/// row per violation. Producers responsible for emitting this event
/// reside in the Pro overlay (the open-core lint runner today exposes
/// per-engine `RunCompleted` events through the violation store's
/// stream; the Pro overlay aggregates these into a project-wide
/// completion event with the correct run id, timestamp, and snapshot
/// of every active violation).
@immutable
class LintRunCompletionEvent {
  /// Creates a [LintRunCompletionEvent].
  const LintRunCompletionEvent({
    required this.runId,
    required this.runTimestamp,
    required this.dataPoints,
    this.projectPath,
  });

  /// Stable identifier for the run — typically `run-<millis>` for
  /// the seed implementation.
  final String runId;

  /// UTC timestamp the run completed at.
  final DateTime runTimestamp;

  /// One data point per violation reported in the run, post-
  /// transformer-chain (suppressions and severity overrides already
  /// applied).
  final List<ViolationTrendDataPoint> dataPoints;

  /// Root path of the project the run executed against, or `null`
  /// when the producer had no project loaded.
  ///
  /// The completion-event bus is app-wide (one root bus fed by every
  /// tab's per-tab dispatcher), so per-tab consumers — bookmark
  /// stale-detection, Verible auto-run — use this to ignore
  /// completions that belong to a different tab's project.
  final String? projectPath;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LintRunCompletionEvent) return false;
    if (runId != other.runId) return false;
    if (runTimestamp != other.runTimestamp) return false;
    if (projectPath != other.projectPath) return false;
    if (dataPoints.length != other.dataPoints.length) return false;
    for (var i = 0; i < dataPoints.length; i++) {
      if (dataPoints[i] != other.dataPoints[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    runId,
    runTimestamp,
    projectPath,
    Object.hashAll(dataPoints),
  );

  @override
  String toString() =>
      'LintRunCompletionEvent('
      'runId: $runId, runTimestamp: $runTimestamp, '
      'projectPath: $projectPath, dataPoints: ${dataPoints.length})';
}
