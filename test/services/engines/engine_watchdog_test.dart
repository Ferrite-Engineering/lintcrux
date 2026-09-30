// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/services/engines/timeout_engine_watchdog.dart';

/// Unit coverage for the [TimeoutEngineWatchdog].
///
/// The watchdog is the seam that keeps a hung engine from hanging the app:
/// it must kill (via `onTimeout`) and surface [EngineTimedOutException]
/// when a stream stalls, and be completely transparent for a stream that
/// completes within budget.
void main() {
  const watchdog = TimeoutEngineWatchdog();

  test(
    'hung stream → onTimeout fires and stream errors with timeout',
    () async {
      var killed = false;
      Object? caught;
      final hung = StreamController<int>();
      addTearDown(hung.close);
      final closed = Completer<void>();

      watchdog
          .guard<int>(
            hung.stream,
            timeout: const Duration(milliseconds: 80),
            engineId: 'verilator',
            onTimeout: () => killed = true,
          )
          .listen(
            (_) {},
            onError: (Object e) => caught = e,
            onDone: closed.complete,
          );

      await closed.future.timeout(const Duration(seconds: 5));
      expect(killed, isTrue, reason: 'watchdog must kill the subprocess');
      expect(caught, isA<EngineTimedOutException>());
      expect((caught! as EngineTimedOutException).engineId, 'verilator');
    },
  );

  test('stream completing within budget → transparent passthrough', () async {
    var killed = false;
    final out = await watchdog
        .guard<int>(
          Stream<int>.fromIterable(<int>[1, 2, 3]),
          timeout: const Duration(seconds: 30),
          engineId: 'verible',
          onTimeout: () => killed = true,
        )
        .toList();
    expect(out, <int>[1, 2, 3]);
    expect(killed, isFalse);
  });

  test(
    'progressing stream resets the inactivity budget (not killed)',
    () async {
      var killed = false;
      final controller = StreamController<int>();
      final received = <int>[];
      final sub = watchdog
          .guard<int>(
            controller.stream,
            timeout: const Duration(milliseconds: 120),
            engineId: 'slang',
            onTimeout: () => killed = true,
          )
          .listen(received.add, onError: (Object _) {});

      // Emit every 40 ms for ~160 ms — each event resets the 120 ms budget.
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        controller.add(i);
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(killed, isFalse, reason: 'a progressing engine is never killed');
      expect(received, <int>[0, 1, 2, 3]);
      await sub.cancel();
      await controller.close();
    },
  );
}
