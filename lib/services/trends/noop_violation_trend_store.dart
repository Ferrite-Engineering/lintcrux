// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/violation_trend_store.dart';
import 'package:lintcrux/domain/models/lint_run_completion_event.dart';
import 'package:lintcrux/domain/models/trend_retention_policy.dart';
import 'package:lintcrux/domain/models/violation_trend_aggregate.dart';
import 'package:lintcrux/domain/models/violation_trend_data_point.dart';

/// Open-core in-memory [ViolationTrendStore].
///
/// Trend tracking is a Pro feature. This is the default of
/// `violationTrendStoreProvider`, which the open core never reads; the Pro
/// overlay overrides the provider with the SQLite-backed
/// `SqliteViolationTrendStore`. It accepts ingestions and announces them on
/// the broadcast stream, but retains the data only in memory — the same
/// relationship `NoopBaselineStore` has to `JsonFileBaselineStore`.
class NoopViolationTrendStore implements ViolationTrendStore {
  /// Creates a [NoopViolationTrendStore].
  NoopViolationTrendStore();

  final List<ViolationTrendDataPoint> _points = <ViolationTrendDataPoint>[];
  final StreamController<void> _events = StreamController<void>.broadcast();

  @override
  Future<void> ingestRunCompletion(LintRunCompletionEvent event) async {
    _points.addAll(event.dataPoints);
    _events.add(null);
  }

  @override
  Future<int> countRunsWithoutProject({DateTime? since}) async => 0;

  @override
  Future<List<ViolationTrendDataPoint>> queryDataPoints({
    String? ruleId,
    Severity? severity,
    String? filePathGlob,
    DateTime? since,
    int? limit,
    int? offset,
    String? projectPath,
  }) async {
    var filtered = _points.where((p) {
      if (ruleId != null && p.ruleId != ruleId) return false;
      if (severity != null && p.severity != severity) return false;
      if (since != null && p.runTimestamp.isBefore(since)) return false;
      // Glob filtering is intentionally substring-match in the noop
      // store — the Pro SQLite store supports true glob semantics.
      if (filePathGlob != null && !p.filePath.contains(filePathGlob)) {
        return false;
      }
      return true;
    }).toList()..sort((a, b) => b.runTimestamp.compareTo(a.runTimestamp));
    final start = offset ?? 0;
    final end = limit == null
        ? filtered.length
        : (start + limit).clamp(0, filtered.length);
    if (start >= filtered.length) return const [];
    filtered = filtered.sublist(start, end);
    return List<ViolationTrendDataPoint>.unmodifiable(filtered);
  }

  @override
  Future<List<ViolationTrendAggregate>> queryAggregates({
    required ViolationTrendAggregateKey key,
    required Duration windowSize,
    DateTime? since,
    String? projectPath,
  }) async {
    // The noop store does not bucket — it returns an empty list. The
    // Pro SqliteViolationTrendStore computes buckets via SQL.
    return const [];
  }

  @override
  Future<int> applyRetention(TrendRetentionPolicy policy) async {
    final before = _points.length;
    if (policy.maxAgeDays != null) {
      final cutoff = DateTime.now().toUtc().subtract(
        Duration(days: policy.maxAgeDays!),
      );
      _points.removeWhere((p) => p.runTimestamp.isBefore(cutoff));
    }
    if (policy.maxRunsRetained != null) {
      // Group by runId, sort by latest run timestamp, prune oldest.
      final byRun = <String, DateTime>{};
      for (final p in _points) {
        final existing = byRun[p.runId];
        if (existing == null || p.runTimestamp.isAfter(existing)) {
          byRun[p.runId] = p.runTimestamp;
        }
      }
      if (byRun.length > policy.maxRunsRetained!) {
        final sortedRunIds = byRun.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        final keep = sortedRunIds
            .sublist(sortedRunIds.length - policy.maxRunsRetained!)
            .map((e) => e.key)
            .toSet();
        _points.removeWhere((p) => !keep.contains(p.runId));
      }
    }
    final deleted = before - _points.length;
    if (deleted > 0) _events.add(null);
    return deleted;
  }

  @override
  Future<TrendStorageStats> storageStats() async {
    if (_points.isEmpty) return TrendStorageStats.empty;
    final distinctRuns = _points.map((p) => p.runId).toSet().length;
    var oldest = _points.first.runTimestamp;
    var newest = _points.first.runTimestamp;
    for (final p in _points) {
      if (p.runTimestamp.isBefore(oldest)) oldest = p.runTimestamp;
      if (p.runTimestamp.isAfter(newest)) newest = p.runTimestamp;
    }
    return TrendStorageStats(
      dataPointCount: _points.length,
      distinctRunCount: distinctRuns,
      oldestPointAt: oldest,
      newestPointAt: newest,
    );
  }

  @override
  Stream<void> get dataChanged => _events.stream;

  /// Disposes the broadcast stream. Call from `ref.onDispose`.
  Future<void> dispose() => _events.close();
}
