// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_menu_bar/crux_menu_bar.dart';
import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_descriptor.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_descriptors.dart';
import 'package:lintcrux/core/shortcuts/menu_layout.dart';

void main() {
  group('kMenuLayout', () {
    test('covers exactly the menu-visible action set', () {
      final placed = <LintcruxAction>{
        ...cruxMenuLayoutActions(kMenuLayout),
        ...kAppMenuActions.desktopFolded,
      };
      final menuVisible = LintcruxAction.values
          .where(
            (a) =>
                descriptorFor(a).surfaces.contains(LintcruxActionSurface.menu),
          )
          .toSet();
      expect(
        placed,
        equals(menuVisible),
        reason:
            'A menu-visible action is missing from kMenuLayout (or the table '
            'places an action that is no longer menu-visible). Give it a home '
            'in the appropriate category group in menu_layout.dart.',
      );
    });

    test('places no action more than once', () {
      final seen = <LintcruxAction>{};
      for (final groups in kMenuLayout.values) {
        for (final group in groups) {
          for (final action in group) {
            expect(
              seen.add(action),
              isTrue,
              reason: '$action appears more than once in kMenuLayout',
            );
          }
        }
      }
    });

    test('does not place the app-folded actions (Settings / Quit)', () {
      final placed = cruxMenuLayoutActions(kMenuLayout);
      for (final action in kAppMenuActions.desktopFolded) {
        expect(placed, isNot(contains(action)));
      }
      expect(placed, contains(kAppMenuActions.about));
      expect(placed, contains(kAppMenuActions.checkForUpdates));
    });

    test('places each action in the category its own mapping declares', () {
      kMenuLayout.forEach((category, groups) {
        for (final group in groups) {
          for (final action in group) {
            expect(
              action.category,
              category,
              reason:
                  '$action is placed under $category but its category is '
                  '${action.category}',
            );
          }
        }
      });
    });

    test('leads View with the command palette and Help with Documentation', () {
      expect(kMenuLayout[ActionCategory.view]!.first, [
        LintcruxAction.openCommandPalette,
      ]);
      expect(kMenuLayout[ActionCategory.help]!.first, [
        LintcruxAction.openDocumentation,
      ]);
      expect(kMenuLayout[ActionCategory.help]!.last, [
        LintcruxAction.openAbout,
      ]);
    });

    test('ends Tools with the diagnostics group', () {
      expect(kMenuLayout[ActionCategory.tools]!.last, [
        LintcruxAction.openTabDiagnostics,
        LintcruxAction.openAppDiagnostics,
      ]);
    });

    test('puts the exports in File, not Tools', () {
      final file = kMenuLayout[ActionCategory.file]!.expand((g) => g);
      expect(
        file,
        containsAll([
          LintcruxAction.exportSarif,
          LintcruxAction.exportJson,
          LintcruxAction.exportCsv,
          LintcruxAction.exportHtml,
        ]),
      );
    });

    test('declares no Edit or Navigate menu', () {
      // LintCrux has no editing or navigation actions, so neither renders.
      // Previously Navigate was silently omitted because it happened to be
      // empty; now that is explicit.
      expect(kMenuLayout.containsKey(ActionCategory.edit), isFalse);
      expect(kMenuLayout.containsKey(ActionCategory.navigate), isFalse);
    });
  });

  group('duplicate removal', () {
    test('the filter-preset and session actions have exactly one spelling', () {
      // There used to be two actions per behaviour, four menu rows for two
      // functions: saveFilterPreset/savePresetFromCurrentFilter,
      // manageFilterPresets/openFilterPresetManager, and
      // saveSession/exportTabAsSession — each pair dispatching to the same
      // provider. The names below are the survivors; the enum must not grow
      // the removed spellings back.
      final names = LintcruxAction.values.map((a) => a.name).toSet();
      expect(names, contains('saveFilterPreset'));
      expect(names, contains('manageFilterPresets'));
      expect(names, contains('saveSession'));
      expect(names, isNot(contains('savePresetFromCurrentFilter')));
      expect(names, isNot(contains('openFilterPresetManager')));
      expect(names, isNot(contains('exportTabAsSession')));
    });
  });
}
