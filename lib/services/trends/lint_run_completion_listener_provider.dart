// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/trend_ingest_failure.dart';
import 'package:lintcrux/services/trends/lint_run_completion_event_provider.dart';
import 'package:lintcrux/services/trends/trend_ingest_diagnostics_provider.dart';
import 'package:lintcrux/services/trends/violation_trend_store_provider.dart';

/// Auto-listening provider that pumps every
/// [LintRunCompletionEvent] from
/// [lintRunCompletionEventProvider] into the active
/// [ViolationTrendStore].
///
/// Declared in the open core and realized only by the Pro overlay, which
/// lists it in the `eagerStartupProvidersProvider` seam: the app then holds
/// a root-container subscription on it for the whole session, so ingestion
/// runs whether or not any chart screen has been opened, and cannot be
/// paused by widget lifecycle. A `read`-only realization would not do: an
/// un-listened provider is paused, and the pause propagates into the
/// `ref.listen` below, silently dropping every completion event.
///
/// The overlay supplies the producer and the SQLite store; this provider
/// ties them together. Mirrors the SimCrux `trendRecordingListenerProvider`
/// shape so cross-suite readers see the same pattern.
///
/// Failure handling: the store call is fire-and-forget (non-async on
/// purpose, so a slow SQLite write does not stall the stream), but its
/// failures are NOT swallowed. Both resolving the store seam and the
/// ingest future itself are guarded here, and every failure is reported
/// to [trendIngestDiagnosticsSinkProvider] — whose default logs, and whose
/// Pro binding also raises a user-visible signal. A failed ingest
/// never propagates out of the callback, so one bad write cannot tear
/// down the subscription and stop all subsequent runs from being
/// recorded.
final Provider<void> lintRunCompletionListenerProvider = Provider<void>(
  (ref) {
    void report(String runId, Object error, StackTrace stackTrace) {
      // The ingest future outlives this provider: `catchError` below fires
      // after an async gap, and a tab closed (or an app shut down) mid-write
      // disposes this listener first. `ref.read` on a disposed Ref throws
      // UnmountedRefException, out of an unawaited future — so the reporting
      // path for a failed write became a second, louder failure with no
      // handler. The Pro sink cannot be captured up-front to dodge this: it
      // reads a notifier off the same ref when invoked.
      //
      // Dropping the report is the honest outcome here rather than a
      // swallowed error: the surfaces it would reach — the log line, the Pro
      // user-visible signal — belong to a scope that no longer exists.
      if (!ref.mounted) return;
      ref.read(trendIngestDiagnosticsSinkProvider)(
        TrendIngestFailure(
          runId: runId,
          error: error,
          stackTrace: stackTrace,
          occurredAt: DateTime.now().toUtc(),
        ),
      );
    }

    ref.listen(
      lintRunCompletionEventProvider,
      (previous, next) {
        next.whenData((event) {
          try {
            unawaited(
              ref
                  .read(violationTrendStoreProvider)
                  .ingestRunCompletion(event)
                  .catchError(
                    (Object error, StackTrace stackTrace) =>
                        report(event.runId, error, stackTrace),
                  ),
            );
          } on Object catch (error, stackTrace) {
            // Resolving the store seam itself threw — e.g. a backing
            // database whose open failed outright.
            report(event.runId, error, stackTrace);
          }
        });
      },
    );
  },
);
