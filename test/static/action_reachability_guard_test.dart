// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_descriptors.dart';
import 'package:lintcrux/core/shortcuts/shortcut_bindings.dart';

/// Every action must be reachable, or be listed here with the reason it is not.
///
/// ## The defect class this closes
///
/// A suite audit's single most expensive finding was work that shipped and
/// then had no way in. An action's `surfaces` set is one line, it is silent
/// when empty, and nothing checked it:
///
///  * LintCrux Pro's entire multi-project feature set (project switcher,
///    reopen recent, cross-project search) was built, tier-badged,
///    telemetry-instrumented, and reachable by nobody. It shipped and was
///    recorded as done; a later "hide the stub actions" pass emptied the
///    surface sets. Neither side saw the other.
///  * SimCrux's `dispatchPrAnnotations` had a working dispatcher and no
///    menu entry, while the website described the menu entry's behaviour
///    in detail.
///  * NetCrux's X-Trace engine computed a correct result into a provider
///    nothing rendered, while its documentation called it shipped at three
///    altitudes.
///
/// Each was found by a human reading code. This makes the machine read it.
///
/// ## Why an allowlist rather than a blanket ban
///
/// A surfaceless action is sometimes correct — a focus command bound only to a
/// chord, or an engine whose UI genuinely has not been built. What is never
/// correct is an *unexplained* one. The allowlist is a map so every entry
/// carries its reason: an allowance without one is indistinguishable from an
/// oversight six months later, which is precisely how the multi-project
/// defect survived.
///
/// When a surface lands, delete the entry. When one is emptied, this fails.
///
/// ## A declared surface is only worth something if it is mounted
///
/// This guard reads the descriptor table, so on its own it credits an action
/// with a surface nobody renders — `forceLintRunWithoutCache` claimed the
/// toolbar, which has no control for it. The other two halves live elsewhere:
/// `test/core/shortcuts/action_surface_conformance_test.dart` pumps each
/// surface widget and asserts it renders exactly the actions the table gives
/// it (in both directions for the hand-placed toolbar), and
/// `import_reachability_guard_test.dart` proves those widgets' files are
/// reached from the entry points — `DesktopMenuBar` and
/// `CommandPaletteDialog` from `lib/app.dart`, `LintcruxToolbar` from the
/// viewer scaffold.
const _allowedSurfaceless = <LintcruxAction, String>{
  // Empty. switchProject, reopenRecentProject and searchAcrossProjects once
  // sat here in spirit — built, tier-badged, telemetry-instrumented and
  // reachable by nobody. All three now declare menu + palette surfaces.
  // Keep this empty.
};

void main() {
  test('every action is reachable, or explains why not', () {
    final offenders = <String>[];

    for (final action in LintcruxAction.values) {
      final hasSurface = descriptorFor(action).surfaces.isNotEmpty;
      if (hasSurface) {
        // A surfaced action that is ALSO on the allowlist means the allowance
        // outlived the problem. Fail, so the list cannot rot.
        if (_allowedSurfaceless.containsKey(action)) {
          offenders.add(
            '${action.name}: now has a surface but is still allowlisted — '
            'delete its entry from _allowedSurfaceless',
          );
        }
        continue;
      }
      if (_allowedSurfaceless.containsKey(action)) continue;
      offenders.add(
        '${action.name}: declares no ActionSurface, so it appears in no menu, '
        'no palette and no toolbar. If that is deliberate, add it to '
        '_allowedSurfaceless with the reason. If not, give it a surface — '
        'this is the built-but-unreachable defect class.',
      );
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('an allowlisted action still has a keybinding to reach it by', () {
    // The allowlist exists for actions reachable some OTHER way. An entry with
    // no surface and no chord is not an exception to the rule — it is the bug
    // the rule is about, wearing an exemption.
    final unreachable = <String>[];
    for (final action in _allowedSurfaceless.keys) {
      final bound = defaultBindings().containsKey(action);
      if (!bound) {
        unreachable.add(
          '${action.name}: allowlisted as surfaceless AND has no default '
          'keybinding — it is reachable by nothing. Either give it a surface, '
          'give it a chord, or delete the action.',
        );
      }
    }
    expect(unreachable, isEmpty, reason: unreachable.join('\n'));
  });

  test('the guard is not vacuous', () {
    // If the enum or the descriptor table moved, every check above would pass
    // trivially.
    expect(LintcruxAction.values.length, greaterThan(10));
    expect(
      LintcruxAction.values.where(
        (a) => descriptorFor(a).surfaces.isNotEmpty,
      ),
      isNotEmpty,
      reason: 'no action has any surface — the descriptor table is not loading',
    );
  });
}
