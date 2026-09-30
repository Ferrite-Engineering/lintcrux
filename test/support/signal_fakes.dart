// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

/// An engine subprocess that records the signals it was sent.
///
/// Stands in for a running `yosys` in a `ProcessRegistry`, so a test can see
/// the reaper reach it without the suite depending on what the host has
/// installed. `kill` is the only member the registry uses; every other member
/// throws, so a caller that starts depending on one fails at that call site.
class KillRecordingProcess implements Process {
  /// Every signal [kill] received, in order.
  final List<ProcessSignal> kills = <ProcessSignal>[];

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    kills.add(signal);
    return true;
  }

  Never _unsupported(String member) => throw UnsupportedError(
    'KillRecordingProcess.$member was read; only kill is modelled.',
  );

  @override
  Future<int> get exitCode => _unsupported('exitCode');

  @override
  int get pid => _unsupported('pid');

  @override
  Stream<List<int>> get stderr => _unsupported('stderr');

  @override
  IOSink get stdin => _unsupported('stdin');

  @override
  Stream<List<int>> get stdout => _unsupported('stdout');
}

/// A signal source for `YosysSignalReaper` that delivers [signal] as soon as
/// it is listened for, and nothing for any other signal.
///
/// "As soon as it is listened for" is the shape of a signal landing while the
/// guarded work is still running: the delivery is queued the moment the
/// handler is installed, ahead of anything the work itself awaits.
Stream<ProcessSignal> Function(ProcessSignal) deliverOnListen(
  ProcessSignal signal,
) =>
    (watched) => watched == signal
    ? Stream<ProcessSignal>.value(watched)
    : const Stream<ProcessSignal>.empty();
