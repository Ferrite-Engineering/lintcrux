// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/lint_run_completion_event.dart';
import 'package:lintcrux/domain/models/trend_retention_policy.dart';
import 'package:lintcrux/domain/models/violation_trend_aggregate.dart';
import 'package:lintcrux/domain/models/violation_trend_data_point.dart';
import 'package:lintcrux/services/trends/noop_violation_trend_store.dart';

LintRunCompletionEvent _runEvent(
  String runId,
  DateTime t,
  List<ViolationTrendDataPoint> points,
) => LintRunCompletionEvent(
  runId: runId,
  runTimestamp: t,
  dataPoints: points,
);

ViolationTrendDataPoint _dp(
  String runId,
  DateTime t,
  String ruleId, {
  Severity severity = Severity.warning,
  String filePath = '/p/a.sv',
}) => ViolationTrendDataPoint(
  runId: runId,
  runTimestamp: t,
  ruleId: ruleId,
  severity: severity,
  filePath: filePath,
  message: 'm',
);

void main() {
  group('NoopViolationTrendStore', () {
    test('ingest + queryDataPoints round-trips ingested data', () async {
      final store = NoopViolationTrendStore();
      addTearDown(store.dispose);
      final t = DateTime.utc(2026, 5, 25);
      await store.ingestRunCompletion(
        _runEvent('r1', t, [_dp('r1', t, 'verilator/A')]),
      );
      final out = await store.queryDataPoints();
      expect(out, hasLength(1));
      expect(out.first.runId, 'r1');
      expect(out.first.ruleId, 'verilator/A');
    });

    test('queryDataPoints filters by ruleId', () async {
      final store = NoopViolationTrendStore();
      addTearDown(store.dispose);
      final t = DateTime.utc(2026, 5, 25);
      await store.ingestRunCompletion(
        _runEvent('r1', t, [
          _dp('r1', t, 'verilator/A'),
          _dp('r1', t, 'verilator/B'),
        ]),
      );
      final out = await store.queryDataPoints(ruleId: 'verilator/A');
      expect(out, hasLength(1));
      expect(out.first.ruleId, 'verilator/A');
    });

    test('queryDataPoints filters by severity', () async {
      final store = NoopViolationTrendStore();
      addTearDown(store.dispose);
      final t = DateTime.utc(2026, 5, 25);
      await store.ingestRunCompletion(
        _runEvent('r1', t, [
          _dp('r1', t, 'verilator/A'),
          _dp('r1', t, 'verilator/B', severity: Severity.error),
        ]),
      );
      final errors = await store.queryDataPoints(severity: Severity.error);
      expect(errors, hasLength(1));
      expect(errors.first.severity, Severity.error);
    });

    test('queryDataPoints filters by since timestamp', () async {
      final store = NoopViolationTrendStore();
      addTearDown(store.dispose);
      final older = DateTime.utc(2026, 5, 24);
      final newer = DateTime.utc(2026, 5, 25);
      await store.ingestRunCompletion(
        _runEvent('rOld', older, [_dp('rOld', older, 'X')]),
      );
      await store.ingestRunCompletion(
        _runEvent('rNew', newer, [_dp('rNew', newer, 'X')]),
      );
      final recent = await store.queryDataPoints(since: newer);
      expect(recent, hasLength(1));
      expect(recent.first.runId, 'rNew');
    });

    test('queryDataPoints orders newest first', () async {
      final store = NoopViolationTrendStore();
      addTearDown(store.dispose);
      final older = DateTime.utc(2026, 5, 24);
      final newer = DateTime.utc(2026, 5, 25);
      await store.ingestRunCompletion(
        _runEvent('rOld', older, [_dp('rOld', older, 'X')]),
      );
      await store.ingestRunCompletion(
        _runEvent('rNew', newer, [_dp('rNew', newer, 'X')]),
      );
      final out = await store.queryDataPoints();
      expect(out.map((p) => p.runId), ['rNew', 'rOld']);
    });

    test('queryDataPoints applies limit + offset', () async {
      final store = NoopViolationTrendStore();
      addTearDown(store.dispose);
      final t = DateTime.utc(2026, 5, 25);
      await store.ingestRunCompletion(
        _runEvent('r1', t, [
          _dp('r1', t, 'A'),
          _dp('r1', t, 'B'),
          _dp('r1', t, 'C'),
        ]),
      );
      final first = await store.queryDataPoints(limit: 2);
      expect(first, hasLength(2));
      final rest = await store.queryDataPoints(offset: 2);
      expect(rest, hasLength(1));
    });

    test('queryAggregates returns empty list (noop posture)', () async {
      final store = NoopViolationTrendStore();
      addTearDown(store.dispose);
      final t = DateTime.utc(2026, 5, 25);
      await store.ingestRunCompletion(
        _runEvent('r1', t, [_dp('r1', t, 'X')]),
      );
      final out = await store.queryAggregates(
        key: ViolationTrendAggregateKey.global,
        windowSize: const Duration(days: 1),
      );
      expect(out, isEmpty);
    });

    test('applyRetention prunes by maxAgeDays', () async {
      final store = NoopViolationTrendStore();
      addTearDown(store.dispose);
      final stale = DateTime.now().toUtc().subtract(const Duration(days: 200));
      final fresh = DateTime.now().toUtc().subtract(const Duration(days: 10));
      await store.ingestRunCompletion(
        _runEvent('rOld', stale, [_dp('rOld', stale, 'X')]),
      );
      await store.ingestRunCompletion(
        _runEvent('rNew', fresh, [_dp('rNew', fresh, 'X')]),
      );
      final deleted = await store.applyRetention(
        const TrendRetentionPolicy(maxAgeDays: 90),
      );
      expect(deleted, 1);
      final remaining = await store.queryDataPoints();
      expect(remaining, hasLength(1));
      expect(remaining.first.runId, 'rNew');
    });

    test('applyRetention prunes by maxRunsRetained', () async {
      final store = NoopViolationTrendStore();
      addTearDown(store.dispose);
      for (var i = 0; i < 5; i++) {
        final t = DateTime.utc(2026, 5, 1 + i);
        await store.ingestRunCompletion(
          _runEvent('r$i', t, [_dp('r$i', t, 'X')]),
        );
      }
      final deleted = await store.applyRetention(
        const TrendRetentionPolicy(maxRunsRetained: 3),
      );
      expect(deleted, 2);
      final remaining = await store.queryDataPoints();
      final runIds = remaining.map((p) => p.runId).toSet();
      expect(runIds, {'r2', 'r3', 'r4'});
    });

    test('storageStats reports counts and timestamps', () async {
      final store = NoopViolationTrendStore();
      addTearDown(store.dispose);
      final older = DateTime.utc(2026, 5, 24);
      final newer = DateTime.utc(2026, 5, 25);
      await store.ingestRunCompletion(
        _runEvent('r1', older, [_dp('r1', older, 'X')]),
      );
      await store.ingestRunCompletion(
        _runEvent('r2', newer, [_dp('r2', newer, 'Y')]),
      );
      final stats = await store.storageStats();
      expect(stats.dataPointCount, 2);
      expect(stats.distinctRunCount, 2);
      expect(stats.oldestPointAt, older);
      expect(stats.newestPointAt, newer);
    });

    test('dataChanged emits after ingest and retention', () async {
      final store = NoopViolationTrendStore();
      addTearDown(store.dispose);
      final emits = <void>[];
      final sub = store.dataChanged.listen(emits.add);
      addTearDown(sub.cancel);
      final t = DateTime.utc(2026, 5, 25);
      await store.ingestRunCompletion(
        _runEvent('r1', t, [_dp('r1', t, 'X')]),
      );
      await Future<void>.delayed(Duration.zero);
      expect(emits.length, 1);
      final stale = DateTime.now().toUtc().subtract(const Duration(days: 200));
      await store.ingestRunCompletion(
        _runEvent('rOld', stale, [_dp('rOld', stale, 'X')]),
      );
      await Future<void>.delayed(Duration.zero);
      await store.applyRetention(
        const TrendRetentionPolicy(maxAgeDays: 90),
      );
      await Future<void>.delayed(Duration.zero);
      expect(emits.length, greaterThanOrEqualTo(3));
    });
  });
}
