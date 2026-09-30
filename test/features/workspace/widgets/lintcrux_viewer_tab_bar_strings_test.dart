// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/workspace/widgets/lintcrux_viewer_tab_bar_strings.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

void main() {
  Future<LintcruxViewerTabBarStrings> stringsForLocale(
    WidgetTester tester,
    Locale locale,
  ) async {
    late L10N captured;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          L10N.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10N.supportedLocales,
        home: Builder(
          builder: (context) {
            captured = L10N.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return LintcruxViewerTabBarStrings(captured);
  }

  testWidgets('exposes non-empty strings for the en locale', (tester) async {
    final strings = await stringsForLocale(tester, const Locale('en'));
    expect(strings.closeTabTooltip, isNotEmpty);
    expect(strings.newTabTooltip, isNotEmpty);
    expect(strings.newTabDefaultDisplayName, isNotEmpty);
    expect(strings.unnamedTabFallback, isNotEmpty);
    expect(strings.closeTabMenuItem, isNotEmpty);
    expect(strings.closeOtherTabsMenuItem, isNotEmpty);
    expect(strings.closeTabsToTheRightMenuItem, isNotEmpty);
    expect(strings.moveToNewWindowMenuItem, isNotEmpty);
    expect(strings.multiWindowUnavailableTooltip, isNotEmpty);
    expect(strings.activePaneAccessibilityLabel, isNotEmpty);
    expect(strings.dragToPaneAccessibilityHint, isNotEmpty);
    expect(strings.reorderHandleTooltip, isNotEmpty);
  });

  testWidgets('locale sweep: every supported locale yields non-empty strings', (
    tester,
  ) async {
    for (final locale in L10N.supportedLocales) {
      final strings = await stringsForLocale(tester, locale);
      expect(
        strings.closeTabTooltip,
        isNotEmpty,
        reason: 'closeTabTooltip empty for $locale',
      );
      expect(
        strings.reorderHandleTooltip,
        isNotEmpty,
        reason: 'reorderHandleTooltip empty for $locale',
      );
    }
  });

  testWidgets('each close button names its tab, in every locale', (
    tester,
  ) async {
    final en = await stringsForLocale(tester, const Locale('en'));
    expect(en.closeTabTooltipFor('top.lintcrux'), 'Close top.lintcrux');
    for (final locale in L10N.supportedLocales) {
      final strings = await stringsForLocale(tester, locale);
      expect(
        strings.closeTabTooltipFor('top.lintcrux'),
        allOf(contains('top.lintcrux'), isNot(strings.closeTabTooltip)),
        reason: 'closeTabTooltipFor does not name the tab for $locale',
      );
    }
  });

  testWidgets('zh and zh_CN resolve to identical strings (mirrored ARB)', (
    tester,
  ) async {
    final zh = await stringsForLocale(tester, const Locale('zh'));
    final zhCN = await stringsForLocale(tester, const Locale('zh', 'CN'));
    expect(zh.closeTabTooltip, zhCN.closeTabTooltip);
    expect(zh.newTabTooltip, zhCN.newTabTooltip);
    expect(zh.reorderHandleTooltip, zhCN.reorderHandleTooltip);
  });
}
