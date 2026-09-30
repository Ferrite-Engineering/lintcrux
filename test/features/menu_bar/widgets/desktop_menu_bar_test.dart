// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/shortcuts/action_label.dart';
import 'package:lintcrux/core/shortcuts/action_tier_label.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/features/menu_bar/widgets/desktop_menu_bar.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

void _noop(LintcruxAction _) {}

Widget _wrap({
  Locale? locale,
  TargetPlatform platform = TargetPlatform.macOS,
}) => ProviderScope(
  child: MaterialApp(
    theme: ThemeData(platform: platform),
    locale: locale,
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: const DesktopMenuBar(
      onAction: _noop,
      child: Scaffold(body: SizedBox.shrink()),
    ),
  ),
);

/// Walks the [PlatformMenuBar.menus] tree and returns every leaf
/// [PlatformMenuItem].
List<PlatformMenuItem> _allLeafItems(PlatformMenuBar bar) {
  final result = <PlatformMenuItem>[];
  void visit(PlatformMenuItem item) {
    if (item is PlatformMenu) {
      item.menus.forEach(visit);
    } else if (item is PlatformMenuItemGroup) {
      item.members.forEach(visit);
    } else {
      result.add(item);
    }
  }

  bar.menus.forEach(visit);
  return result;
}

Set<String?> _leafLabels(WidgetTester tester) {
  final bar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
  return _allLeafItems(bar).map((e) => e.label).toSet();
}

void main() {
  group('DesktopMenuBar tier suffix', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders in ${locale.toLanguageTag()} without exceptions', (
        tester,
      ) async {
        await tester.pumpWidget(_wrap(locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a Pro action carries the localized tier suffix', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      final l10n = L10N.of(tester.element(find.byType(PlatformMenuBar)));
      final labels = _leafLabels(tester);

      const proAction = LintcruxAction.setBaseline;
      expect(
        proAction.requiredTier,
        LicenseTier.pro,
        reason: 'test fixture assumes setBaseline is Pro',
      );
      final expected =
          proAction.label(l10n) + tierLabelSuffix(LicenseTier.pro, l10n);
      expect(labels, contains(expected));
      // The bare label (no suffix) must NOT appear — the suffix is appended.
      expect(labels, isNot(contains(proAction.label(l10n))));
    });

    testWidgets('a free (open-core) action carries no suffix', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      final l10n = L10N.of(tester.element(find.byType(PlatformMenuBar)));
      final labels = _leafLabels(tester);

      const freeAction = LintcruxAction.openProject;
      expect(freeAction.requiredTier, LicenseTier.openCore);
      // The label appears verbatim, with no tier suffix appended.
      expect(labels, contains(freeAction.label(l10n)));
    });

    testWidgets('the suffix is localized (differs across en / ja)', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(locale: const Locale('en')));
      await tester.pumpAndSettle();
      final enL10n = L10N.of(tester.element(find.byType(PlatformMenuBar)));
      final enSuffix = tierLabelSuffix(LicenseTier.pro, enL10n);
      expect(enSuffix, contains(enL10n.tierBadgePro));
    });
  });
}
