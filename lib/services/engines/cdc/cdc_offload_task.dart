// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// One computation running off the calling isolate. See `runOffloaded`.
abstract interface class OffloadTask<R> {
  /// The computation's value, or its error, or [OffloadCancelled] when
  /// [cancel] got there first.
  Future<R> get result;

  /// Whether the computation ended up running on the calling isolate: the
  /// platform has no isolates, or the computation (or something it captures)
  /// could not be sent to one. Only meaningful once [result] has completed.
  bool get ranInProcess;

  /// Stops the computation: the isolate is killed and [result] completes with
  /// [OffloadCancelled]. Idempotent, and a no-op once [result] has completed.
  void cancel();
}

/// Completes [OffloadTask.result] when the task was cancelled.
final class OffloadCancelled implements Exception {
  /// Creates the marker.
  const OffloadCancelled();

  @override
  String toString() => 'OffloadCancelled';
}
