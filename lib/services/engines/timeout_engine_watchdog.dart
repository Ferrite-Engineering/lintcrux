// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/interfaces/engine_watchdog.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';

/// Default [EngineWatchdog] — a real, active implementation (not a no-op).
///
/// Uses [Stream.timeout] so the guard is an *inactivity* budget: the timer
/// resets on every event the engine emits and is cancelled when the engine
/// stream completes or errors. A hung engine (no output, never exits)
/// produces no events, so the very first gap exceeds [Duration] and trips
/// the guard; a legitimately long-but-progressing engine that streams
/// violations keeps resetting the timer and is never killed prematurely.
///
/// On expiry: [onTimeout] runs first (the orchestrator passes
/// [LintEngine.cancel], which kills the subprocess), then the wrapped
/// stream emits an [EngineTimedOutException] and closes. [Stream.timeout]
/// cancels the upstream subscription when the sink closes, so the engine's
/// generator stops and no further events leak through.
class TimeoutEngineWatchdog implements EngineWatchdog {
  /// Creates a [TimeoutEngineWatchdog].
  const TimeoutEngineWatchdog();

  @override
  Stream<T> guard<T>(
    Stream<T> source, {
    required Duration timeout,
    required String engineId,
    required void Function() onTimeout,
  }) {
    return source.timeout(
      timeout,
      onTimeout: (sink) {
        // Kill the subprocess before surfacing the error so there is no
        // window where the run is reported failed but the engine is still
        // alive.
        onTimeout();
        sink
          ..addError(
            EngineTimedOutException(engineId: engineId, timeout: timeout),
          )
          ..close();
      },
    );
  }
}
