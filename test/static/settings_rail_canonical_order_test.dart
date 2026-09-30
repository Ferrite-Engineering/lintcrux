// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Guards the Settings rail's category order against
// `CruxSettingsCategoryId.canonicalOrder` (crux_settings_ui) — the
// suite-shared rail order every product follows. `canonicalOrder`'s
// own doc comment says "Order is asserted by each product's settings
// conformance test" — until now nothing in LintCrux did that:
// `_SettingsBody` in `settings_screen.dart` builds its category list using
// `CruxSettingsCategoryId.general` / `.appearance` / `.privacy` /
// `.productDefaults` / `.editors` / `.cxp` / `.shortcuts` in that literal
// source order, correct only because nobody had reordered it since, with no
// test to catch a future edit that put two categories out of order.
//
// Mirrors the other suite products' equivalent guards: pumps the real
// `SettingsScreen` and reads the actual `CruxSettingsMasterDetail.categories`
// it renders — the real widget tree, not a copy of the source list — so a
// future reorder in `settings_screen.dart` is caught by running the screen,
// not by grep.

import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/settings/screens/settings_screen.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

void main() {
  testWidgets(
    'the rendered settings-rail id order is a subsequence of '
    'CruxSettingsCategoryId.canonicalOrder',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: [
              L10N.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: L10N.supportedLocales,
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final masterDetail = tester.widget<CruxSettingsMasterDetail>(
        find.byType(CruxSettingsMasterDetail),
      );
      final renderedIds = masterDetail.categories
          .map((c) => c.id)
          .toList(growable: false);

      // Not vacuous: a broken widget-tree change that stopped mounting
      // CruxSettingsMasterDetail, or a screen that rendered zero
      // categories, must not pass this guard by having nothing left to
      // check.
      expect(
        renderedIds,
        isNotEmpty,
        reason:
            'SettingsScreen rendered no categories — either the widget '
            'tree changed shape or CruxSettingsMasterDetail was not found',
      );

      // Every id LintCrux renders must actually be a canonical id (a
      // typo'd or ad-hoc id would otherwise silently fall out of the
      // subsequence check below rather than failing loudly).
      for (final id in renderedIds) {
        expect(
          CruxSettingsCategoryId.canonicalOrder,
          contains(id),
          reason:
              'rendered settings category id "$id" is not in '
              'CruxSettingsCategoryId.canonicalOrder — either it is a typo, '
              'or a new canonical id needs adding to crux_settings_ui first',
        );
      }

      // Strictly-increasing-index subsequence: LintCrux's own categories may
      // skip canonical ids it does not implement (fileHandling, orientation,
      // remoteControl, extensions, detectors, and ai are other products'),
      // but whichever ids it does render must appear in the SAME relative
      // order canonicalOrder prescribes — never out of order. Pro-contributed
      // `CruxSettingsExtraCategory` entries always render last (per
      // `canonicalOrder`'s own doc comment) and carry `pro.*` ids that are
      // not in `canonicalOrder` at all, so this test only pumps the
      // open-core screen — the Pro overlay asserts its own `pro.license`-first
      // ordering in its own test suite.
      var lastIndex = -1;
      for (final id in renderedIds) {
        final index = CruxSettingsCategoryId.canonicalOrder.indexOf(id);
        expect(
          index,
          greaterThan(lastIndex),
          reason:
              'settings rail order violation: "$id" (canonical index '
              '$index) rendered after something with canonical index '
              '$lastIndex or later — rendered order was '
              '${renderedIds.join(" > ")}',
        );
        lastIndex = index;
      }
    },
  );
}
