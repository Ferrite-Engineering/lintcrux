// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';

/// Kills every Yosys process this process spawned when the *process*
/// is asked to terminate.
///
/// The sibling of `YosysProcessReaper`, for hosts that have no widget
/// tree. `crux_yosys` records each spawned process in a
/// [ProcessRegistry] but deliberately does not depend on Flutter, so
/// draining the registry is the host's job — and the two hosts learn
/// they are going away by completely different mechanisms:
///
/// | host | teardown signal |
/// | --- | --- |
/// | desktop app | `AppLifecycleState.detached` via `WidgetsBindingObserver` |
/// | headless CLI | `SIGINT` / `SIGTERM` via `ProcessSignal.watch` |
///
/// Without this, cancelling a CI job (which sends `SIGTERM` to the
/// process group, then `SIGKILL` after a grace period) can strand a
/// `yosys` elaborating a large design — it is the runner's child, not
/// ours, once we die without cleaning up. The symptom is a CI runner
/// that stays pegged at 100% CPU after the job is cancelled, which is
/// exactly the sort of thing nobody attributes to the linter.
///
/// `SIGTERM` cannot be watched on Windows; [install] skips it there and
/// relies on `SIGINT` (Ctrl-C), which Dart does surface.
class YosysSignalReaper {
  /// Creates a reaper draining [registry]. Defaults to the process-wide
  /// registry `DefaultProcessRunner` writes into.
  ///
  /// [watch] is where signals come from, [ProcessSignal.watch] unless a test
  /// supplies its own: the handlers are process-wide, and a test that raised a
  /// real SIGINT or SIGTERM would race the test runner's own.
  YosysSignalReaper({
    ProcessRegistry? registry,
    Stream<ProcessSignal> Function(ProcessSignal signal)? watch,
  }) : _registry = registry ?? ProcessRegistry.instance,
       _watch = watch ?? _watchProcess;

  static Stream<ProcessSignal> _watchProcess(ProcessSignal signal) =>
      signal.watch();

  final ProcessRegistry _registry;
  final Stream<ProcessSignal> Function(ProcessSignal signal) _watch;
  final List<StreamSubscription<ProcessSignal>> _subscriptions =
      <StreamSubscription<ProcessSignal>>[];

  /// Number of processes signalled by the most recent reap. Zero until a
  /// signal has been handled. Exposed for tests and diagnostics.
  int get lastKillCount => _lastKillCount;
  int _lastKillCount = 0;

  /// Starts watching for termination signals.
  ///
  /// [onSignal] runs after the registry is drained — the entrypoint uses
  /// it to exit with the conventional `128 + signal` code. When
  /// [onSignal] is null the handler only reaps and lets the default
  /// disposition take over on the next signal.
  void install({void Function(ProcessSignal signal)? onSignal}) {
    final signals = <ProcessSignal>[
      ProcessSignal.sigint,
      // Watching SIGTERM throws on Windows; Ctrl-C (SIGINT) is the only
      // one the Dart VM exposes there.
      if (!Platform.isWindows) ProcessSignal.sigterm,
    ];
    for (final signal in signals) {
      _subscriptions.add(
        _watch(signal).listen((s) {
          _lastKillCount = _registry.killAll();
          onSignal?.call(s);
        }),
      );
    }
  }

  /// Drains the registry immediately, without waiting for a signal.
  /// Called on the normal exit path so a run that finished while an
  /// engine subprocess was still winding down does not leak it.
  int reapNow() => _lastKillCount = _registry.killAll();

  /// Stops watching. Idempotent.
  Future<void> dispose() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
  }
}
