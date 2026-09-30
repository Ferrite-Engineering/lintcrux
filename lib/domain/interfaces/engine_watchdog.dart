// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/interfaces/lint_engine.dart';

/// Bounds the wall-clock duration of a single [LintEngine] run.
///
/// The orchestration layer ([ParallelEngineRunner]) fans engines out
/// concurrently and consumes each engine's [LintEngine.run] stream. A hung
/// or runaway engine produces no terminal event, so without a watchdog the
/// whole run — and the UI waiting on it — hangs forever. The watchdog
/// wraps each engine's violation stream so that if it neither emits an
/// event nor completes within [timeout], the run is aborted:
///
/// 1. [onTimeout] is invoked — the orchestrator passes [LintEngine.cancel],
///    which kills the underlying subprocess (no zombie left running).
/// 2. The returned stream errors with an [EngineTimedOutException] so the
///    orchestrator marks *this* engine failed while the others keep going.
///
/// This is an open-core extension point: the default
/// `TimeoutEngineWatchdog` is a real (not no-op) implementation, and the
/// timeout duration comes from `engineTimeoutProvider` (user-configurable
/// via Settings). It is intentionally simple — a single inactivity budget,
/// not a CPU/memory cgroup — because the failure mode it guards against
/// (an engine that never finishes) is observable purely from the stream.
// ignore: one_member_abstracts
abstract class EngineWatchdog {
  /// Wraps [source] (a single engine's violation stream) with a wall-clock
  /// guard.
  ///
  /// If [source] does not produce an event or complete within [timeout],
  /// [onTimeout] is invoked and the returned stream errors with an
  /// [EngineTimedOutException] carrying [engineId] and [timeout], then
  /// closes. When [source] completes or errors normally before the budget
  /// elapses, the returned stream forwards those events verbatim and the
  /// guard is a no-op (transparent for fast engines).
  Stream<T> guard<T>(
    Stream<T> source, {
    required Duration timeout,
    required String engineId,
    required void Function() onTimeout,
  });
}
