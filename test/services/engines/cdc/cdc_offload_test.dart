// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/engines/cdc/cdc_offload.dart';

// The helper that moves the CDC netlist read and analysis off the UI isolate.

/// The computation under test, built where nothing but its arguments can be
/// captured, the way the engine builds its own.
int Function() _sum(List<int> values) =>
    () => values.fold(0, (a, b) => a + b);

String? Function() _isolateName() =>
    () => Isolate.current.debugName;

void main() {
  test('runs on another isolate and returns the value', () async {
    final task = runOffloaded<int>(_sum(<int>[1, 2, 3]));
    expect(await task.result, 6);
    expect(task.ranInProcess, isFalse);
  });

  test('the computation is not on the calling isolate', () async {
    final name = await runOffloaded<String?>(_isolateName()).result;
    expect(name, isNotNull);
    expect(name, isNot(Isolate.current.debugName));
  });

  test('an error in the computation reaches the caller with its type', () {
    final task = runOffloaded<int>(() => throw const FormatException('bad'));
    expect(task.result, throwsA(isA<FormatException>()));
  });

  test('cancel kills a computation that would never finish', () async {
    final started = Stopwatch()..start();
    final task = runOffloaded<int>(() {
      while (true) {}
    });
    await Future<void>.delayed(const Duration(milliseconds: 200));
    task.cancel();
    await expectLater(task.result, throwsA(isA<OffloadCancelled>()));
    expect(started.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('cancel after completion changes nothing', () async {
    final task = runOffloaded<int>(_sum(<int>[4, 5]));
    expect(await task.result, 9);
    task.cancel();
    expect(await task.result, 9);
  });

  test('a computation that cannot be sent runs here instead', () async {
    final port = RawReceivePort();
    addTearDown(port.close);
    final task = runOffloaded<int>(() => port.hashCode * 0 + 7);
    expect(await task.result, 7);
    expect(task.ranInProcess, isTrue);
  });
}
