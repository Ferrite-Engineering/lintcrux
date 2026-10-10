// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:lintcrux/core/shortcuts/shortcut_manager_widget.dart';

Widget _harness({
  Map<LintcruxAction, VoidCallback> handlers = const {},
  Widget? child,
}) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: ShortcutManagerWidget(
          handlers: handlers,
          // Focus(autofocus: true) ensures a focused widget exists so
          // Shortcuts fires.
          child:
              child ?? const Focus(autofocus: true, child: SizedBox.expand()),
        ),
      ),
    ),
  );
}

void main() {
  group('ShortcutManagerWidget — handler dispatch', () {
    // Using LintcruxAction.runAllEngines (bare F5) and cancelRun
    // (Esc) means these tests do not need a platform override —
    // both bindings are identical across macOS / Linux / Windows.

    testWidgets('fires the registered handler when F5 is pressed', (
      tester,
    ) async {
      var fired = false;
      await tester.pumpWidget(
        _harness(handlers: {LintcruxAction.runAllEngines: () => fired = true}),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pump();
      expect(fired, isTrue);
    });

    testWidgets('does not fire on a non-matching key', (tester) async {
      var fired = false;
      await tester.pumpWidget(
        _harness(handlers: {LintcruxAction.runAllEngines: () => fired = true}),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.pump();
      expect(fired, isFalse);
    });

    testWidgets(
      'fires the correct handler among multiple registrations',
      (tester) async {
        var runFired = false;
        var cancelFired = false;
        await tester.pumpWidget(
          _harness(
            handlers: {
              LintcruxAction.runAllEngines: () => runFired = true,
              LintcruxAction.cancelRun: () => cancelFired = true,
            },
          ),
        );
        await tester.pump();
        // Bare F5 → runAllEngines.
        await tester.sendKeyEvent(LogicalKeyboardKey.f5);
        await tester.pump();
        expect(runFired, isTrue);
        expect(cancelFired, isFalse);

        // Esc → cancelRun.
        runFired = false;
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(cancelFired, isTrue);
        expect(runFired, isFalse);
      },
    );

    testWidgets('does nothing when an action has no registered handler', (
      tester,
    ) async {
      // F5 matches runAllEngines, but the handler map is empty, so the
      // widget must still pump cleanly without firing anything or
      // throwing.
      await tester.pumpWidget(_harness());
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('conflict precedence (issue #36 bug 3)', () {
    testWidgets(
      'a freshly remapped (customized) action wins the chord it collides with',
      (tester) async {
        var runFired = false;
        var cancelFired = false;
        await tester.pumpWidget(
          _harness(
            handlers: {
              LintcruxAction.runAllEngines: () => runFired = true,
              LintcruxAction.cancelRun: () => cancelFired = true,
            },
          ),
        );
        await tester.pump();

        // runAllEngines holds F5 by default. Remap cancelRun ONTO F5, creating a
        // collision where cancelRun is the customized interloper.
        final container = ProviderScope.containerOf(
          tester.element(find.byType(ShortcutManagerWidget)),
        );
        container
            .read(shortcutBindingsProvider.notifier)
            .setBinding(
              LintcruxAction.cancelRun,
              const SingleActivator(LogicalKeyboardKey.f5),
            );
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.f5);
        await tester.pump();

        // The user's remap fires; the default owner is shadowed (does not fire).
        expect(cancelFired, isTrue);
        expect(runFired, isFalse);
      },
    );
  });

  group('ShortcutManagerWidget — Escape and popups', () {
    // As the app mounts it: above the Navigator, so popup routes sit below
    // the manager and a key reaches the manager before the framework's own
    // Escape-dismisses-the-popup handling.
    Widget appHarness({
      required Map<LintcruxAction, VoidCallback> handlers,
      bool Function(LintcruxAction)? isEnabled,
    }) => ProviderScope(
      child: MaterialApp(
        builder: (context, child) => ShortcutManagerWidget(
          handlers: handlers,
          isEnabled: isEnabled,
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Focus(
              autofocus: true,
              child: TextButton(
                onPressed: () => showMenu<void>(
                  context: context,
                  position: const RelativeRect.fromLTRB(10, 10, 10, 10),
                  items: const [
                    PopupMenuItem<void>(child: Text('Waive…')),
                  ],
                ),
                child: const Text('open menu'),
              ),
            ),
          ),
        ),
      ),
    );

    testWidgets('Escape on an open menu closes the menu and does not fire '
        'the bare-Escape action', (tester) async {
      var cancelled = 0;
      await tester.pumpWidget(
        appHarness(handlers: {LintcruxAction.cancelRun: () => cancelled++}),
      );
      await tester.tap(find.text('open menu'));
      await tester.pumpAndSettle();
      expect(find.text('Waive…'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Waive…'), findsNothing);
      expect(cancelled, 0);
    });

    testWidgets('Escape with no popup open still fires the action', (
      tester,
    ) async {
      var cancelled = 0;
      await tester.pumpWidget(
        appHarness(handlers: {LintcruxAction.cancelRun: () => cancelled++}),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(cancelled, 1);
    });

    testWidgets('a disabled action does not fire from its key', (tester) async {
      var cancelled = 0;
      await tester.pumpWidget(
        appHarness(
          handlers: {LintcruxAction.cancelRun: () => cancelled++},
          isEnabled: (action) => action != LintcruxAction.cancelRun,
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(cancelled, 0);
    });
  });
}
