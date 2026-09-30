// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/engines/yosys/yosys_process_reaper.dart';

/// A [ProcessRegistry] that records `killAll` calls instead of signalling
/// anything.
///
/// The unit under test is the *lifecycle policy* — which states reap and
/// which do not — not `ProcessRegistry.killAll` itself, which `crux_yosys`
/// owns and tests. Spawning real children here would also deadlock the
/// widget tests: `testWidgets` runs under fake async, so a real
/// `Process.exitCode` future never completes.
class _RecordingProcessRegistry implements ProcessRegistry {
  int killAllCalls = 0;
  int pending = 0;

  @override
  int get liveCount => pending;

  @override
  int killAll() {
    killAllCalls++;
    final killed = pending;
    pending = 0;
    return killed;
  }

  @override
  void register(Object process) => pending++;

  @override
  void unregister(Object process) => pending--;
}

void main() {
  group('YosysProcessLifecycleObserver', () {
    test('drains the registry on detached', () {
      final registry = _RecordingProcessRegistry()..pending = 2;
      final observer = YosysProcessLifecycleObserver(registry: registry)
        ..didChangeAppLifecycleState(AppLifecycleState.detached);

      expect(registry.killAllCalls, 1);
      expect(observer.lastKillCount, 2);
      expect(registry.liveCount, 0);
    });

    test('leaves processes alone on every non-detached state', () {
      final registry = _RecordingProcessRegistry()..pending = 1;
      final observer = YosysProcessLifecycleObserver(registry: registry);

      // A background lint run must survive the app being minimised,
      // hidden, or backgrounded — only teardown reaps.
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.resumed,
      ]) {
        observer.didChangeAppLifecycleState(state);
        expect(
          registry.killAllCalls,
          0,
          reason: '$state must not reap running Yosys processes',
        );
        expect(registry.liveCount, 1);
      }
      expect(observer.lastKillCount, 0);
    });

    test('detached with an empty registry is a harmless no-op', () {
      final registry = _RecordingProcessRegistry();
      final observer = YosysProcessLifecycleObserver(registry: registry)
        ..didChangeAppLifecycleState(AppLifecycleState.detached);
      expect(observer.lastKillCount, 0);
      expect(registry.killAllCalls, 1);
    });
  });

  group('YosysProcessReaper widget', () {
    testWidgets('a mounted reaper drains the registry on detached', (
      tester,
    ) async {
      final registry = _RecordingProcessRegistry()..pending = 1;
      await tester.pumpWidget(
        YosysProcessReaper(
          registry: registry,
          child: const SizedBox.shrink(),
        ),
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
      await tester.pump();

      expect(
        registry.killAllCalls,
        1,
        reason: 'mounting the reaper must install the lifecycle observer',
      );
      expect(registry.liveCount, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('passes its child through unchanged', (tester) async {
      await tester.pumpWidget(
        YosysProcessReaper(
          registry: _RecordingProcessRegistry(),
          child: const Text('marker', textDirection: TextDirection.ltr),
        ),
      );
      expect(find.text('marker'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
