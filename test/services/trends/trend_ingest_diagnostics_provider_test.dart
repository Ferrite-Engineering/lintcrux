// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/trend_ingest_failure.dart';
import 'package:lintcrux/services/trends/trend_ingest_diagnostics_provider.dart';
import 'package:logging/logging.dart';

TrendIngestFailure _failure({String? runId = 'r1', String? store}) =>
    TrendIngestFailure(
      runId: runId,
      error: StateError('database is locked'),
      stackTrace: StackTrace.current,
      occurredAt: DateTime.utc(2026, 7, 20),
      storeDescription: store,
    );

void main() {
  group('trendIngestDiagnosticsSinkProvider', () {
    test('open-core default is the logging sink', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(trendIngestDiagnosticsSinkProvider),
        same(logTrendIngestFailure),
      );
    });

    test('the default sink accepts a failure without throwing', () {
      // The sink runs inside a fire-and-forget error handler; if it threw
      // it would replace a recorded failure with an unhandled one.
      expect(
        () => logTrendIngestFailure(_failure(store: '/tmp/trends.db')),
        returnsNormally,
      );
    });

    test('the default sink accepts a run-less failure without throwing', () {
      // A store quarantined at open time is not tied to any one run, so
      // `runId` is null and the log line must not read "failed for run
      // null".
      expect(
        () => logTrendIngestFailure(
          _failure(runId: null, store: '/tmp/trends.db'),
        ),
        returnsNormally,
      );
    });

    test('the default sink logs a SEVERE record, which a release build '
        'keeps', () async {
      // It used `developer.log`, which an AOT build drops: the failure never
      // reached the issue reporter's buffer or stderr.
      final records = <LogRecord>[];
      final originalLevel = Logger.root.level;
      Logger.root.level = Level.ALL;
      addTearDown(() => Logger.root.level = originalLevel);
      final sub = Logger.root.onRecord
          .where((r) => r.loggerName == kTrendIngestLogName)
          .listen(records.add);
      addTearDown(sub.cancel);

      logTrendIngestFailure(_failure(runId: 'r4', store: '/tmp/trends.db'));
      await Future<void>.delayed(Duration.zero);

      expect(records, hasLength(1));
      expect(records.single.level, Level.SEVERE);
      expect(records.single.message, contains('r4'));
      expect(records.single.message, contains('/tmp/trends.db'));
      expect(records.single.error, isA<StateError>());
    });

    test('an overlay-style override receives every reported failure', () {
      final received = <TrendIngestFailure>[];
      final container = ProviderContainer(
        overrides: [
          trendIngestDiagnosticsSinkProvider.overrideWithValue(received.add),
        ],
      );
      addTearDown(container.dispose);

      container.read(trendIngestDiagnosticsSinkProvider)(_failure(runId: 'r9'));

      expect(received, hasLength(1));
      expect(received.single.runId, 'r9');
    });
  });

  group('TrendIngestFailure', () {
    test('toString names the run, the store, and the error', () {
      final text = _failure(runId: 'r3', store: '/tmp/trends.db').toString();
      expect(text, contains('r3'));
      expect(text, contains('/tmp/trends.db'));
      expect(text, contains('database is locked'));
    });
  });
}
