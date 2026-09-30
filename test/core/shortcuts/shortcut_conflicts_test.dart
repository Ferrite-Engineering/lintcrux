// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/shortcut_bindings.dart';
import 'package:lintcrux/core/shortcuts/shortcut_conflicts.dart';

void main() {
  group(
    'resolveShortcutConflicts — customization precedence and default-keymap '
    'collision guard',
    () {
      test('a customized remap wins the chord over the default owner', () {
        // runAllEngines holds F5 by default; the user remaps cancelRun onto F5.
        const f5 = SingleActivator(LogicalKeyboardKey.f5);
        final r = resolveShortcutConflicts({
          LintcruxAction.runAllEngines: f5, // == its default → owner
          LintcruxAction.cancelRun: f5, // != its default (Esc) → interloper
        });
        // Runtime precedence: the interloper fires; the owner is shadowed.
        expect(
          r.effectiveBindings.containsKey(LintcruxAction.cancelRun),
          isTrue,
        );
        expect(
          r.effectiveBindings.containsKey(LintcruxAction.runAllEngines),
          isFalse,
        );
        // Asymmetric UI view: both rows agree cancelRun is the winner.
        expect(
          r.conflicts[LintcruxAction.runAllEngines]!.winner,
          LintcruxAction.cancelRun,
        );
        expect(
          r.conflicts[LintcruxAction.cancelRun]!.winner,
          LintcruxAction.cancelRun,
        );
        expect(r.conflictChordCount, 1);
      });

      test('the default keymap has no collisions (every chord is unique)', () {
        // Guards against re-introducing a default collision: toggleTheme and
        // newTab both defaulted to Cmd/Ctrl+T before default-binding
        // collisions were checked at all.
        final r = resolveShortcutConflicts(defaultBindings());
        expect(r.conflicts, isEmpty);
        expect(r.conflictChordCount, 0);
      });
    },
  );
}
