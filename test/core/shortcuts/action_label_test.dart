// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/shortcuts/action_label.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

Future<L10N> _captureL10n(WidgetTester tester, Locale locale) async {
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
  return captured;
}

void main() {
  group('LintcruxActionLabel', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('every action has a non-empty label in $locale', (
        tester,
      ) async {
        final l10n = await _captureL10n(tester, locale);
        for (final action in LintcruxAction.values) {
          final label = action.label(l10n);
          expect(
            label,
            isNotEmpty,
            reason: 'missing label for ${action.name} in $locale',
          );
        }
      });
    }

    testWidgets('labels are unique across the action set (en)', (
      tester,
    ) async {
      final l10n = await _captureL10n(tester, const Locale('en'));
      final seen = <String>{};
      for (final action in LintcruxAction.values) {
        final label = action.label(l10n);
        expect(
          seen.add(label),
          isTrue,
          reason: 'duplicate label "$label" for ${action.name}',
        );
      }
    });
  });
}
