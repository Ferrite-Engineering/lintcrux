// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:lintcrux/features/settings/widgets/settings_general_section.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

const _locales = ['en', 'zh_CN', 'zh', 'ja', 'ko'];
const Key _segmentsKey = ValueKey('cruxAutoReloadSegments');

Locale _locale(String tag) {
  final parts = tag.split('_');
  return parts.length == 2 ? Locale(parts[0], parts[1]) : Locale(parts[0]);
}

/// The auto-reload segments must fit a 320 px settings row in every locale:
/// the owned segmented control does not shrink below its content, so long
/// labels overflow.
void main() {
  for (final tag in _locales) {
    testWidgets('auto-reload segments fit a 320 px row in $tag', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            diagnosticsForcedByBuildModeProvider.overrideWithValue(true),
          ],
          child: MaterialApp(
            locale: _locale(tag),
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: const Scaffold(
              body: SizedBox(width: 320, child: SettingsGeneralSection()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final l10n = lookupL10N(_locale(tag));
      expect(find.text(l10n.settingsAutoReloadPrompt), findsOneWidget);
      expect(find.text(l10n.settingsAutoReloadAuto), findsOneWidget);
      expect(find.text(l10n.settingsAutoReloadOff), findsOneWidget);
      expect(
        tester.getSize(find.byKey(_segmentsKey)).width,
        lessThanOrEqualTo(320),
      );
    });
  }
}
