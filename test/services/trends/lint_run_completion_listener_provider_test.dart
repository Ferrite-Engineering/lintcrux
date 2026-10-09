// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/violation_trend_store.dart';
import 'package:lintcrux/domain/models/lint_run_completion_event.dart';
import 'package:lintcrux/domain/models/trend_ingest_failure.dart';
import 'package:lintcrux/domain/models/trend_retention_policy.dart';
import 'package:lintcrux/domain/models/violation_trend_aggregate.dart';
import 'package:lintcrux/domain/models/violation_trend_data_point.dart';
import 'package:lintcrux/services/trends/lint_run_completion_event_provider.dart';
import 'package:lintcrux/services/trends/lint_run_completion_listener_provider.dart';
import 'package:lintcrux/services/trends/trend_ingest_diagnostics_provider.dart';
import 'package:lintcrux/services/trends/violation_trend_store_provider.dart';

class _RecordingStore implements ViolationTrendStore {
  _RecordingStore({this.failFor = const <String>{}});

  /// Run-ids whose ingest rejects, modelling a locked or full database.
  final Set<String> failFor;

  final List<LintRunCompletionEvent> ingested = <LintRunCompletionEvent>[];

  @override
  Future<void> ingestRunCompletion(LintRunCompletionEvent event) async {
    if (failFor.contains(event.runId)) {
      throw StateError('database is locked');
    }
    ingested.add(event);
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
  }) async => const [];

  @override
  Future<List<ViolationTrendAggregate>> queryAggregates({
    required ViolationTrendAggregateKey key,
    required Duration windowSize,
    DateTime? since,
    String? projectPath,
  }) async => const [];

  @override
  Future<int> applyRetention(TrendRetentionPolicy policy) async => 0;

  @override
  Future<TrendStorageStats> storageStats() async => TrendStorageStats.empty;

  @override
  Stream<void> get dataChanged => const Stream<void>.empty();
}

void main() {
  group('lintRunCompletionListenerProvider', () {
    test('forwards stream events into ingestRunCompletion', () async {
      final controller = StreamController<LintRunCompletionEvent>.broadcast();
      addTearDown(controller.close);
      final store = _RecordingStore();
      final container = ProviderContainer(
        overrides: [
          lintRunCompletionEventProvider.overrideWith((_) => controller.stream),
          violationTrendStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      // Keep the listener provider alive throughout the test so its
      // ref.listen subscription on the stream provider stays active.
      // A bare container.read may dispose Provider<void> immediately
      // once no consumer is holding it.
      final keepAlive = container.listen<void>(
        lintRunCompletionListenerProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(keepAlive.close);
      final streamKeepAlive = container.listen(
        lintRunCompletionEventProvider,
        (_, _) {},
      );
      addTearDown(streamKeepAlive.close);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final event = LintRunCompletionEvent(
        runId: 'r1',
        runTimestamp: DateTime.utc(2026, 5, 25),
        dataPoints: <ViolationTrendDataPoint>[
          ViolationTrendDataPoint(
            runId: 'r1',
            runTimestamp: DateTime.utc(2026, 5, 25),
            ruleId: 'X',
            severity: Severity.warning,
            filePath: '/p/a.sv',
            message: 'm',
          ),
        ],
      );
      controller.add(event);
      // The StreamProvider buffers between an upstream emission and the
      // ref.listen invocation through one or more event-loop turns.
      // Drain a few ticks so the listener has a chance to invoke
      // ingestRunCompletion.
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (store.ingested.isNotEmpty) break;
      }
      expect(store.ingested, [event]);
    });

    test(
      'a failing ingest is logged and the chain survives for later runs',
      () async {
        // Guards the provider doc-comment's failure-handling claim. A
        // store whose write rejects (locked / full database) must not
        // propagate out of the listener callback: if it did, the
        // subscription would tear down and EVERY subsequent run would be
        // dropped, not just the failing one.
        final controller = StreamController<LintRunCompletionEvent>.broadcast();
        addTearDown(controller.close);
        final store = _RecordingStore(failFor: const {'bad'});
        final reported = <TrendIngestFailure>[];
        final container = ProviderContainer(
          overrides: [
            lintRunCompletionEventProvider.overrideWith(
              (_) => controller.stream,
            ),
            violationTrendStoreProvider.overrideWithValue(store),
            trendIngestDiagnosticsSinkProvider.overrideWithValue(reported.add),
          ],
        );
        addTearDown(container.dispose);
        final keepAlive = container.listen<void>(
          lintRunCompletionListenerProvider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(keepAlive.close);
        final streamKeepAlive = container.listen(
          lintRunCompletionEventProvider,
          (_, _) {},
        );
        addTearDown(streamKeepAlive.close);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        controller.add(eventWithRunId('bad'));
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        controller.add(eventWithRunId('good'));
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          if (store.ingested.isNotEmpty) break;
        }

        expect(
          store.ingested.map((e) => e.runId),
          <String>['good'],
          reason:
              'the failing run is dropped but the subscription survives, so '
              'the next run is still recorded',
        );
        expect(
          reported.map((f) => f.runId),
          <String>['bad'],
          reason: 'the failure must not be silent',
        );
        expect(reported.single.error, isA<StateError>());
      },
    );
  });
}

/// Minimal single-point completion event for [runId].
LintRunCompletionEvent eventWithRunId(String runId) => LintRunCompletionEvent(
  runId: runId,
  runTimestamp: DateTime.utc(2026, 5, 25),
  dataPoints: <ViolationTrendDataPoint>[
    ViolationTrendDataPoint(
      runId: runId,
      runTimestamp: DateTime.utc(2026, 5, 25),
      ruleId: 'X',
      severity: Severity.warning,
      filePath: '/p/a.sv',
      message: 'm',
    ),
  ],
);
