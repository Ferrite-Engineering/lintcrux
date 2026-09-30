// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/trend_ingest_failure.dart';
import 'package:lintcrux/services/trends/trend_ingest_log_name.dart';
import 'package:logging/logging.dart';

export 'package:lintcrux/services/trends/trend_ingest_log_name.dart'
    show kTrendIngestLogName;

/// Receives every [TrendIngestFailure] the ingestion listener catches, and
/// every open-time trend-store fault the Pro store reports (a quarantined
/// database, which carries no run id).
typedef TrendIngestDiagnosticsSink = void Function(TrendIngestFailure failure);

/// Open-core extension point for trend-ingestion failure reporting.
///
/// The default logs under [kTrendIngestLogName] and does nothing else.
/// Nothing in the open core reports here: the ingestion listener and the
/// store that can fail are both realized by the Pro overlay.
///
/// The Pro overlay overrides this with a sink that logs AND
/// raises a one-time user-visible signal, because the Pro store writes a
/// real SQLite database that genuinely can be locked, full, or
/// read-only. Without a visible signal the only symptom is charts that
/// stay empty forever, which reads as "trend tracking is broken" rather
/// than "the database could not be written".
final Provider<TrendIngestDiagnosticsSink> trendIngestDiagnosticsSinkProvider =
    Provider<TrendIngestDiagnosticsSink>((_) => logTrendIngestFailure);

/// Default sink: logs [failure] at SEVERE under [kTrendIngestLogName].
///
/// Through `package:logging`, not `developer.log`, which emits nothing from a
/// release build: a SEVERE record reaches the issue reporter's buffer and
/// stderr. The Pro overlay's sink calls this too, before raising its notice.
void logTrendIngestFailure(TrendIngestFailure failure) {
  final runId = failure.runId;
  Logger(kTrendIngestLogName).severe(
    '${runId == null ? 'Trend store failure' : 'Trend ingestion failed for run $runId'}'
    '${failure.storeDescription == null ? '' : ' (${failure.storeDescription})'}',
    failure.error,
    failure.stackTrace,
  );
}
