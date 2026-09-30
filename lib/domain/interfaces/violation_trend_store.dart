// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/lint_run_completion_event.dart';
import 'package:lintcrux/domain/models/trend_retention_policy.dart';
import 'package:lintcrux/domain/models/violation_trend_aggregate.dart';
import 'package:lintcrux/domain/models/violation_trend_data_point.dart';

/// Persistent storage for cross-run violation history.
///
/// Trend tracking (Pro tier) records every violation from every completed lint
/// run into the store and drives the per-rule / severity-drift / project /
/// heatmap chart screens off the resulting history.
///
/// Open Core ships [NoopViolationTrendStore] (records nothing,
/// returns empty queries) so the seam is testable without the Pro
/// SQLite implementation. The Pro overlay supplies
/// `SqliteViolationTrendStore` via `sqflite_common_ffi`, persistent
/// at `<appSupportDir>/lintcrux/trends.db`.
///
/// The interface intentionally mirrors SimCrux's `TrendStore` shape so
/// cross-suite consumers who look at one product's trend code can quickly
/// orient on the other product's.
abstract class ViolationTrendStore {
  /// Records every data point in [event] into the store. Batch-
  /// inserts when the backing storage supports transactions.
  Future<void> ingestRunCompletion(LintRunCompletionEvent event);

  /// Returns data points matching the filter, ordered by
  /// `runTimestamp` descending (newest first).
  ///
  /// - [ruleId] / [severity] / [filePathGlob] — narrow the result.
  /// - [since] — only include points at or after this UTC timestamp.
  /// - [limit] / [offset] — paginate.
  /// - [projectPath] — restrict to one project's runs.
  ///
  /// **[projectPath] is not optional in the sense that it looks.** `trends.db`
  /// is a single app-wide file that pools every project the user has ever
  /// linted, so omitting it returns *everything* — which is right for a
  /// cross-project view and wrong, silently, for any surface that says
  /// "project". The Pro project trend chart omitted it and rendered one
  /// codebase's improvement inside another's history.
  ///
  /// Rows written before schema v3 carry `project_path` NULL and match no
  /// [projectPath]: their project is genuinely unknown and guessing would
  /// file one project's history under another's. A caller that filters should
  /// tell the user how many runs it left out — see
  /// [countRunsWithoutProject].
  Future<List<ViolationTrendDataPoint>> queryDataPoints({
    String? ruleId,
    Severity? severity,
    String? filePathGlob,
    DateTime? since,
    int? limit,
    int? offset,
    String? projectPath,
  });

  /// How many recorded runs carry no project attribution at all.
  ///
  /// These are the pre-v3 rows. They are invisible to any
  /// [queryDataPoints] call that passes a `projectPath`, so a project-scoped
  /// chart needs this number to say "N earlier runs are not attributed to a
  /// project and are not shown" rather than quietly dropping a user's whole
  /// back catalogue the day they upgrade.
  ///
  /// [since] bounds it to the same window the chart is showing.
  Future<int> countRunsWithoutProject({DateTime? since}) async => 0;

  /// Returns time-bucketed aggregates for the given [key].
  ///
  /// [windowSize] controls the bucket width. [since] is optional —
  /// when null, the store returns aggregates over its entire
  /// retained history.
  Future<List<ViolationTrendAggregate>> queryAggregates({
    required ViolationTrendAggregateKey key,
    required Duration windowSize,
    DateTime? since,
  });

  /// Enforces [policy] on the underlying storage, deleting any data
  /// points that violate the policy's age or run-count limits.
  /// Returns the number of points deleted.
  Future<int> applyRetention(TrendRetentionPolicy policy);

  /// Snapshot of current storage utilization.
  Future<TrendStorageStats> storageStats();

  /// Broadcast stream that emits after every ingestion or pruning
  /// that mutates the underlying storage. UI consumers (chart
  /// screens, banners) listen to refresh without polling.
  /// Implementations that cannot detect mutations expose a never-
  /// emitting stream.
  Stream<void> get dataChanged;
}
