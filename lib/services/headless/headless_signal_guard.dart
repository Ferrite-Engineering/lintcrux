// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:lintcrux/services/engines/yosys/yosys_signal_reaper.dart';

/// What a headless LintCrux command does when it is cancelled.
///
/// A CI runner cancels a job by signalling it: `SIGTERM`, then `SIGKILL`
/// after a grace period, or `SIGINT` from a terminal. The command has one
/// chance to act, and it does two things with it, in this order:
///
/// 1. **Reap.** Every engine subprocess this process started is killed. A
///    `yosys` elaborating a large design is the runner's child once its
///    parent dies without cleaning up, and the symptom is an agent pegged at
///    100% CPU after the job that owned it is gone.
/// 2. **Exit `128 + N`**, the code a shell reports for a process stopped by
///    signal N — 130 for `SIGINT`, 143 for `SIGTERM`. Never another code: a
///    pipeline branching on `$?` must be able to tell "cancelled" from any
///    outcome of the lint itself, and every small code is already one of
///    those.
///
/// One implementation for every headless command. The plain lint run wraps
/// its pipeline in [run], and so does anything else that starts engines — a
/// second, hand-written handler is how a command ends up with none.
class HeadlessSignalGuard {
  /// Creates a guard.
  ///
  /// [programName] prefixes the one line printed when a signal arrives.
  /// [enabled] `false` installs no handler, which is what tests want: the
  /// handlers are process-wide and would fight the test runner's. The engines
  /// are still reaped when the guarded work finishes, either way.
  ///
  /// [reaperFactory] and [exitWith] are test seams. The defaults are a
  /// [YosysSignalReaper] on the process-wide registry and `exit`.
  HeadlessSignalGuard({
    this.programName = 'lintcrux',
    this.enabled = true,
    YosysSignalReaper Function()? reaperFactory,
    void Function(int code)? exitWith,
  }) : _reaperFactory = reaperFactory ?? YosysSignalReaper.new,
       _exitWith = exitWith ?? exit;

  /// The name the binary answers to, as its diagnostics print it.
  final String programName;

  /// Whether [run] installs signal handlers.
  final bool enabled;

  final YosysSignalReaper Function() _reaperFactory;
  final void Function(int code) _exitWith;

  /// The exit code of a process stopped by [signal]: `128 + N`.
  static int exitCodeFor(ProcessSignal signal) => 128 + signal.signalNumber;

  /// Runs [body] with the handlers installed, and reaps whatever engine
  /// subprocess is still alive when it finishes, however it finishes.
  ///
  /// A signal that arrives while [body] is running reaps first and exits
  /// second; the exit does not wait for [body].
  Future<T> run<T>(
    Future<T> Function() body, {
    required void Function(String line) stderrSink,
  }) async {
    final reaper = _reaperFactory();
    if (enabled) {
      reaper.install(
        onSignal: (signal) {
          stderrSink('$programName: received $signal, terminating');
          _exitWith(exitCodeFor(signal));
        },
      );
    }
    try {
      return await body();
    } finally {
      // A run that finished while an engine was still winding down must not
      // leave it behind either.
      reaper.reapNow();
      await reaper.dispose();
    }
  }
}
