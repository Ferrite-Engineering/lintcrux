// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/crux_keybindings.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/shortcuts/keymap_presets.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/shortcut_bindings.dart';

void main() {
  group('bindingsForPreset', () {
    test('lintCrux preset round-trips through presetForBindings', () {
      // Can't use `equals(defaultBindings())` — SingleActivator has no ==.
      expect(presetForBindings(defaultBindings()), KeymapPreset.lintCrux);
    });

    test('lintCrux preset equals the defaults action-by-action', () {
      final defaults = defaultBindings();
      final preset = bindingsForPreset(KeymapPreset.lintCrux);
      expect(preset.length, defaults.length);
      for (final action in LintcruxAction.values) {
        expect(
          KeyBindingResolver.activatorsEqual(preset[action], defaults[action]),
          isTrue,
          reason: '${action.name} should match its default',
        );
      }
    });
  });

  group('presetForBindings', () {
    test(
      'identifies an independently-built default map (by-value equality)',
      () {
        // Two defaultBindings() calls build distinct SingleActivator instances;
        // only value comparison via KeyBindingResolver.activatorsEqual matches.
        expect(
          presetForBindings(bindingsForPreset(KeymapPreset.lintCrux)),
          KeymapPreset.lintCrux,
        );
      },
    );

    test('returns null (Custom) for a hand-edited map', () {
      final custom =
          Map<LintcruxAction, ShortcutActivator>.of(defaultBindings())
            ..[LintcruxAction.focusSearch] = const SingleActivator(
              LogicalKeyboardKey.keyJ,
              control: true,
            );
      expect(presetForBindings(custom), isNull);
    });

    test('returns null (Custom) when an action is unbound', () {
      final custom = Map<LintcruxAction, ShortcutActivator>.of(
        defaultBindings(),
      )..remove(LintcruxAction.focusSearch);
      expect(presetForBindings(custom), isNull);
    });
  });
}
