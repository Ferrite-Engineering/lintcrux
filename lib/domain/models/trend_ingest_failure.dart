// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// A failure in the violation trend store — most often a failed attempt to
/// record one completed lint run, but also an open-time fault such as a
/// database quarantined because its bytes were unreadable.
///
/// Trend ingestion is fire-and-forget on the UI thread: a failure must
/// neither stall the run pipeline nor tear down the ingestion
/// subscription. It must also not vanish — a locked or full trends
/// database otherwise drops trend history forever while every chart
/// silently renders empty. This model is what the ingestion listener
/// hands to `trendIngestDiagnosticsSinkProvider` so the failure can be
/// logged and surfaced.
class TrendIngestFailure {
  /// Creates a [TrendIngestFailure].
  const TrendIngestFailure({
    required this.error,
    required this.stackTrace,
    required this.occurredAt,
    this.runId,
    this.storeDescription,
  });

  /// Run-id of the completion event that could not be recorded, or `null`
  /// when the failure was not tied to a single run — a database
  /// quarantined at open time, for instance, which loses history that was
  /// already written rather than a run that was about to be.
  final String? runId;

  /// The thrown error. Typically a storage-layer exception.
  final Object error;

  /// Stack trace captured at the failure site.
  final StackTrace stackTrace;

  /// UTC timestamp of the failure.
  final DateTime occurredAt;

  /// Optional human-readable identification of the backing store (e.g.
  /// the database path), for diagnostics output. `null` when the store
  /// seam itself could not be resolved.
  final String? storeDescription;

  @override
  String toString() =>
      'TrendIngestFailure(runId: $runId, store: $storeDescription, '
      'error: $error)';
}
