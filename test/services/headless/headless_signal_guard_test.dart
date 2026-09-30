// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/engines/yosys/yosys_signal_reaper.dart';
import 'package:lintcrux/services/headless/headless_signal_guard.dart';

import '../../support/signal_fakes.dart';

void main() {
  // Deliberately no real SIGINT/SIGTERM: the handlers are process-wide and a
  // delivered signal would race the test runner's own. The reaper's signal
  // source is the seam instead.

  test('the exit code is 128 + the signal number', () {
    expect(HeadlessSignalGuard.exitCodeFor(ProcessSignal.sigint), 130);
    expect(HeadlessSignalGuard.exitCodeFor(ProcessSignal.sigterm), 143);
  });

  group('a signal during the run', () {
    for (final signal in <ProcessSignal>[
      ProcessSignal.sigint,
      // SIGTERM cannot be watched on Windows; the reaper does not ask.
      if (!Platform.isWindows) ProcessSignal.sigterm,
    ]) {
      test('$signal reaps the engines, then exits 128+N', () async {
        final registry = ProcessRegistry();
        final child = KillRecordingProcess();
        registry.register(child);
        final exits = <int>[];
        final err = <String>[];
        var reapedFirst = false;
        final signalled = Completer<void>();

        final guard = HeadlessSignalGuard(
          programName: 'hostcli',
          reaperFactory: () => YosysSignalReaper(
            registry: registry,
            watch: deliverOnListen(signal),
          ),
          exitWith: (code) {
            reapedFirst = child.kills.isNotEmpty;
            exits.add(code);
            signalled.complete();
          },
        );

        // The body finishes only once the handler has run, which is the
        // shape of a signal landing while an engine is still going.
        final result = await guard.run(
          () async {
            await signalled.future;
            return 'body finished';
          },
          stderrSink: err.add,
        );

        expect(result, 'body finished');
        expect(exits, <int>[HeadlessSignalGuard.exitCodeFor(signal)]);
        expect(reapedFirst, isTrue, reason: 'reap before exit, not after');
        expect(child.kills, <ProcessSignal>[ProcessSignal.sigkill]);
        expect(err.single, 'hostcli: received $signal, terminating');
      });
    }
  });

  test('a run that finishes normally still reaps what is left', () async {
    final registry = ProcessRegistry();
    final child = KillRecordingProcess();
    registry.register(child);
    final exits = <int>[];

    final guard = HeadlessSignalGuard(
      reaperFactory: () => YosysSignalReaper(
        registry: registry,
        watch: (_) => const Stream<ProcessSignal>.empty(),
      ),
      exitWith: exits.add,
    );
    final code = await guard.run(() async => 0, stderrSink: (_) {});

    expect(code, 0);
    expect(exits, isEmpty);
    expect(child.kills, <ProcessSignal>[ProcessSignal.sigkill]);
    expect(registry.liveCount, 0);
  });

  test('a run that throws still reaps what is left', () async {
    final registry = ProcessRegistry();
    final child = KillRecordingProcess();
    registry.register(child);

    final guard = HeadlessSignalGuard(
      reaperFactory: () => YosysSignalReaper(
        registry: registry,
        watch: (_) => const Stream<ProcessSignal>.empty(),
      ),
      exitWith: (_) {},
    );

    await expectLater(
      guard.run<int>(() async => throw StateError('boom'), stderrSink: (_) {}),
      throwsStateError,
    );
    expect(child.kills, <ProcessSignal>[ProcessSignal.sigkill]);
  });

  test('disabled, it watches nothing', () async {
    final watched = <ProcessSignal>[];
    final guard = HeadlessSignalGuard(
      enabled: false,
      reaperFactory: () => YosysSignalReaper(
        registry: ProcessRegistry(),
        watch: (signal) {
          watched.add(signal);
          return const Stream<ProcessSignal>.empty();
        },
      ),
      exitWith: (_) => fail('a disabled guard must never exit'),
    );
    await guard.run(() async => 0, stderrSink: (_) {});
    expect(watched, isEmpty);
  });
}
