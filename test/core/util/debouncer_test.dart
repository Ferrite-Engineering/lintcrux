// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_async/crux_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The violation filter's rule and file fields debounce through the shared
  // `Debouncer`, which replaced a LintCrux copy of the same class. These are
  // the behaviours the filter relies on, kept here so a change to the shared
  // class that altered them fails in this repository too.
  //
  // `testWidgets` runs the body inside the binding's fake-async zone, so the
  // Debouncer's real `Timer` is driven by `tester.pump(duration)` — no wall
  // clock, no flakiness. A pending timer at test end would fail the test, which
  // also proves `dispose`/`cancel` clear it.
  group('Debouncer', () {
    testWidgets('fires once after the trailing delay, with the last action', (
      tester,
    ) async {
      final d = Debouncer();
      var fired = 0;
      var lastValue = '';
      for (final v in ['a', 'ab', 'abc']) {
        d.run(() {
          fired++;
          lastValue = v;
        });
        await tester.pump(const Duration(milliseconds: 50)); // < duration
      }
      expect(fired, 0, reason: 'no fire while calls keep coming');
      await tester.pump(const Duration(milliseconds: 200));
      expect(fired, 1, reason: 'exactly one trailing fire');
      expect(lastValue, 'abc', reason: 'fires with the latest action');
      d.dispose();
    });

    testWidgets('a settled call fires, then a later call fires again', (
      tester,
    ) async {
      final d = Debouncer();
      var fired = 0;
      d.run(() => fired++);
      await tester.pump(const Duration(milliseconds: 200));
      expect(fired, 1);
      d.run(() => fired++);
      await tester.pump(const Duration(milliseconds: 200));
      expect(fired, 2);
      d.dispose();
    });

    testWidgets('cancel / dispose prevents a pending callback from firing', (
      tester,
    ) async {
      final d = Debouncer();
      var fired = 0;
      d
        ..run(() => fired++)
        ..cancel();
      expect(d.isActive, isFalse);
      await tester.pump(const Duration(milliseconds: 500));
      expect(fired, 0);

      d
        ..run(() => fired++)
        ..dispose();
      await tester.pump(const Duration(milliseconds: 500));
      expect(fired, 0);
    });
  });
}
