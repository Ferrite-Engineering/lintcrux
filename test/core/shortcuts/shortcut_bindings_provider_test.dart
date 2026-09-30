// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/crux_keybindings.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/shortcuts/keymap_presets.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/shortcut_bindings.dart';
import 'package:lintcrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

// SingleActivator doesn't override `==`, so we compare structurally
// across trigger key and modifiers when asserting binding equality.
Matcher _sameActivator(SingleActivator expected) => predicate<Object?>(
  (actual) {
    if (actual is! SingleActivator) return false;
    return actual.trigger == expected.trigger &&
        actual.control == expected.control &&
        actual.meta == expected.meta &&
        actual.alt == expected.alt &&
        actual.shift == expected.shift;
  },
  'SingleActivator structurally equal to $expected',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shortcutBindingsProvider', () {
    test('initializes from defaultBindings()', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final actual = container.read(shortcutBindingsProvider);
      final expected = defaultBindings();
      expect(actual.keys.toSet(), expected.keys.toSet());
    });

    test('setBinding overrides one action and leaves others intact', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(shortcutBindingsProvider.notifier);
      final before = Map.of(container.read(shortcutBindingsProvider));

      const replacement = SingleActivator(
        LogicalKeyboardKey.f9,
        control: true,
      );
      notifier.setBinding(LintcruxAction.runAllEngines, replacement);

      final after = container.read(shortcutBindingsProvider);
      expect(
        after[LintcruxAction.runAllEngines],
        _sameActivator(replacement),
      );
      // Other entries unchanged (identity comparison — the notifier
      // copies the map but reuses the activator instances).
      for (final entry in before.entries) {
        if (entry.key == LintcruxAction.runAllEngines) continue;
        expect(identical(after[entry.key], entry.value), isTrue);
      }
    });

    test('reset restores the platform default for a single action', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(shortcutBindingsProvider.notifier);
      const replacement = SingleActivator(LogicalKeyboardKey.f12);
      notifier
        ..setBinding(LintcruxAction.openProject, replacement)
        ..reset(LintcruxAction.openProject);
      final defaults = defaultBindings();
      expect(
        container.read(shortcutBindingsProvider)[LintcruxAction.openProject],
        _sameActivator(
          defaults[LintcruxAction.openProject]! as SingleActivator,
        ),
      );
    });

    test('reset on a default-unbound action removes any custom binding', () {
      // checkForUpdates ships with no default accelerator (openAbout, the
      // previous fixture here, has the suite-wide F1 default), so reset must
      // remove the entry entirely rather than restore a default.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(shortcutBindingsProvider.notifier);
      const custom = SingleActivator(LogicalKeyboardKey.f9);
      notifier
        ..setBinding(LintcruxAction.checkForUpdates, custom)
        ..reset(LintcruxAction.checkForUpdates);
      expect(
        container
            .read(shortcutBindingsProvider)
            .containsKey(LintcruxAction.checkForUpdates),
        isFalse,
      );
    });

    test('resetAll wipes every custom binding back to defaults', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(shortcutBindingsProvider.notifier)
        ..setBinding(
          LintcruxAction.openProject,
          const SingleActivator(LogicalKeyboardKey.f4),
        )
        ..setBinding(
          LintcruxAction.quit,
          const SingleActivator(LogicalKeyboardKey.f6),
        )
        ..resetAll();
      final defaults = defaultBindings();
      final actual = container.read(shortcutBindingsProvider);
      expect(actual.length, defaults.length);
      for (final entry in defaults.entries) {
        expect(
          actual[entry.key],
          _sameActivator(entry.value as SingleActivator),
        );
      }
    });
  });

  group('persistence', () {
    final action = LintcruxAction.values.first;

    ProviderContainer persistentContainer(SharedPreferences prefs) =>
        ProviderContainer(
          overrides: [
            shortcutBindingsStoreProvider.overrideWithValue(
              KeyBindingsStore<LintcruxAction>(
                codec: lintCruxKeymapCodec,
                prefsOverride: prefs,
              ),
            ),
          ],
        );

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('currentDiffs is empty until something changes', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(shortcutBindingsProvider.notifier).currentDiffs(),
        isEmpty,
      );
    });

    test('a rebind survives into a fresh container (relaunch path)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final first = persistentContainer(prefs);
      first
          .read(shortcutBindingsProvider.notifier)
          .setBinding(
            action,
            const SingleActivator(LogicalKeyboardKey.keyJ, control: true),
          );
      await settle();
      first.dispose();

      final second = persistentContainer(prefs);
      addTearDown(second.dispose);
      second.read(shortcutBindingsProvider);
      await settle();

      final restored =
          second.read(shortcutBindingsProvider)[action]! as SingleActivator;
      expect(restored.trigger, LogicalKeyboardKey.keyJ);
      expect(restored.control, isTrue);
    });

    test('unbind then relaunch keeps the action unbound', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final first = persistentContainer(prefs);
      first.read(shortcutBindingsProvider.notifier).unbind(action);
      await settle();
      first.dispose();

      final second = persistentContainer(prefs);
      addTearDown(second.dispose);
      second.read(shortcutBindingsProvider);
      await settle();
      expect(
        second.read(shortcutBindingsProvider).containsKey(action),
        isFalse,
      );
    });

    test('resetAll clears persisted overrides', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final first = persistentContainer(prefs);
      first.read(shortcutBindingsProvider.notifier)
        ..setBinding(
          action,
          const SingleActivator(LogicalKeyboardKey.keyJ, control: true),
        )
        ..resetAll();
      await settle();
      first.dispose();

      final second = persistentContainer(prefs);
      addTearDown(second.dispose);
      second.read(shortcutBindingsProvider);
      await settle();
      expect(
        second.read(shortcutBindingsProvider.notifier).currentDiffs(),
        isEmpty,
      );
    });

    test('importDiffs applies + persists a keymap', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final first = persistentContainer(prefs);
      first.read(shortcutBindingsProvider.notifier).importDiffs({
        action: const KeyBinding(
          key: LogicalKeyboardKey.keyP,
          modifiers: {KeyModifier.mod, KeyModifier.shift},
        ),
      });
      await settle();
      first.dispose();

      final second = persistentContainer(prefs);
      addTearDown(second.dispose);
      second.read(shortcutBindingsProvider);
      await settle();
      final restored =
          second.read(shortcutBindingsProvider)[action]! as SingleActivator;
      expect(restored.trigger, LogicalKeyboardKey.keyP);
      expect(restored.shift, isTrue);
    });

    // After a downgrade the stored keymap is one this build cannot read. The
    // store refuses it by throwing rather than answering "no customizations",
    // precisely so the caller can decline to save over it. The launch restore
    // used to let that refusal escape as an uncaught error and then, on the
    // first rebind, save this build's diffs over the newer keymap.
    test('a keymap written by a newer build is refused and never '
        'overwritten', () async {
      const key = 'settings.shortcutBindings';
      const newer = '{"version": ${kKeymapVersion + 1}, "bindings": {}}';
      SharedPreferences.setMockInitialValues({key: newer});
      final prefs = await SharedPreferences.getInstance();
      final records = <LogRecord>[];
      final originalLevel = Logger.root.level;
      Logger.root.level = Level.ALL;
      addTearDown(() => Logger.root.level = originalLevel);
      final sub = Logger.root.onRecord
          .where((r) => r.loggerName == 'lintcrux.shortcuts')
          .listen(records.add);
      addTearDown(sub.cancel);

      final container = persistentContainer(prefs);
      addTearDown(container.dispose);
      container.read(shortcutBindingsProvider);
      await settle();

      container
          .read(shortcutBindingsProvider.notifier)
          .setBinding(
            action,
            const SingleActivator(LogicalKeyboardKey.keyJ, control: true),
          );
      await settle();

      expect(prefs.getString(key), newer);
      // The session still works, on this build's defaults plus the change.
      final current =
          container.read(shortcutBindingsProvider)[action]! as SingleActivator;
      expect(current.trigger, LogicalKeyboardKey.keyJ);
      expect(records, isNotEmpty);
      expect(records.first.level, Level.WARNING);
    });

    group('applyPreset', () {
      test('replaces the whole map with the supplied preset', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(shortcutBindingsProvider.notifier)
          // Diverge first so the preset visibly replaces a custom binding.
          ..setBinding(
            action,
            const SingleActivator(LogicalKeyboardKey.keyJ, control: true),
          );
        expect(
          presetForBindings(container.read(shortcutBindingsProvider)),
          isNull,
        );

        notifier.applyPreset(bindingsForPreset(KeymapPreset.lintCrux));

        expect(
          presetForBindings(container.read(shortcutBindingsProvider)),
          KeymapPreset.lintCrux,
        );
        // A preset equal to the defaults persists as an empty diff.
        expect(notifier.currentDiffs(), isEmpty);
      });

      test('persists as diff-from-default across a relaunch', () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        final first = persistentContainer(prefs);
        first.read(shortcutBindingsProvider.notifier)
          ..setBinding(
            action,
            const SingleActivator(LogicalKeyboardKey.keyJ, control: true),
          )
          ..applyPreset(bindingsForPreset(KeymapPreset.lintCrux));
        await settle();
        first.dispose();

        final second = persistentContainer(prefs);
        addTearDown(second.dispose);
        second.read(shortcutBindingsProvider);
        await settle();
        expect(
          presetForBindings(second.read(shortcutBindingsProvider)),
          KeymapPreset.lintCrux,
        );
        expect(
          second.read(shortcutBindingsProvider.notifier).currentDiffs(),
          isEmpty,
        );
      });
    });
  });
}
