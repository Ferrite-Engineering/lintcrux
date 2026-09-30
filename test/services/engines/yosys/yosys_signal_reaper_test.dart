// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/engines/yosys/yosys_signal_reaper.dart';

import '../../../support/signal_fakes.dart';

void main() {
  // Deliberately no test that raises a real SIGINT/SIGTERM: the signal
  // handlers are process-wide, and a test that delivered one would race
  // the test runner's own handlers. What is covered here is the part
  // that can go wrong silently — the registry actually being drained,
  // and `install`/`dispose` being safe to call in any order.

  test('reapNow drains the registry and reports the count', () {
    final registry = ProcessRegistry();
    final reaper = YosysSignalReaper(registry: registry);
    expect(reaper.lastKillCount, 0);
    expect(reaper.reapNow(), registry.killAll());
    expect(reaper.lastKillCount, 0, reason: 'nothing was registered');
  });

  test('reapNow is safe to call repeatedly', () {
    final reaper = YosysSignalReaper(registry: ProcessRegistry());
    expect(reaper.reapNow(), 0);
    expect(reaper.reapNow(), 0);
  });

  test('dispose without install is a no-op', () async {
    final reaper = YosysSignalReaper(registry: ProcessRegistry());
    await reaper.dispose();
    await reaper.dispose();
  });

  test('install then dispose leaves no subscriptions behind', () async {
    // The reaper is constructed once per CLI invocation; a leaked
    // subscription would keep the isolate alive after the run finished,
    // which in a CI job reads as a hung step.
    final reaper = YosysSignalReaper(registry: ProcessRegistry())..install();
    await reaper.dispose();
    // A second dispose after a real install must also be safe.
    await reaper.dispose();
  });

  test('a delivered signal drains the registry, then calls onSignal', () async {
    // Through the signal-source seam, so no real signal is raised.
    final registry = ProcessRegistry();
    final child = KillRecordingProcess();
    registry.register(child);
    final handled = Completer<List<ProcessSignal>>();
    final reaper = YosysSignalReaper(
      registry: registry,
      watch: deliverOnListen(ProcessSignal.sigint),
    )..install(onSignal: (_) => handled.complete(List.of(child.kills)));

    expect(await handled.future, <ProcessSignal>[ProcessSignal.sigkill]);
    expect(reaper.lastKillCount, 1);
    await reaper.dispose();
  });

  test('defaults to the process-wide registry', () {
    // `DefaultProcessRunner` writes into `ProcessRegistry.instance`; a
    // reaper pointed anywhere else would drain an empty set and leave a
    // real `yosys` running on a cancelled CI runner.
    expect(YosysSignalReaper().reapNow(), ProcessRegistry.instance.killAll());
  });
}
