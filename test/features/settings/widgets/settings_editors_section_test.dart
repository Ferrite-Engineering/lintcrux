// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/editor/editor_command.dart';
import 'package:lintcrux/features/settings/widgets/settings_editors_section.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/editor/editor_command_provider.dart';

/// Settings → Editors: the Custom preset's executable and arguments fields
/// are form rows, so their labels stay visible while the fields hold the
/// preset's values (the Crux Desktop theme shows a `labelText` only while a
/// field is empty).

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('zh'),
  Locale('ja'),
  Locale('ko'),
];

Widget _harness({Locale locale = const Locale('en')}) => ProviderScope(
  overrides: [
    editorCommandProvider.overrideWith(_CustomEditorNotifier.new),
  ],
  child: MaterialApp(
    theme: cruxThemeForDevice(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      highContrast: false,
      mobile: ThemeData.new,
      platform: TargetPlatform.macOS,
      isWeb: false,
    ),
    locale: locale,
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: const Scaffold(body: SettingsEditorsSection()),
  ),
);

class _CustomEditorNotifier extends EditorCommandNotifier {
  @override
  EditorCommand build() => const EditorCommand(
    preset: EditorPreset.custom,
    executable: 'myeditor',
    argsTemplate: ['--goto', '{file}:{line}'],
  );
}

void main() {
  for (final locale in _locales) {
    testWidgets('the Custom fields keep their labels while they hold a value '
        'in $locale', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_harness(locale: locale));
      await tester.pumpAndSettle();
      final l10n = L10N.of(tester.element(find.byType(SettingsEditorsSection)));

      // Both fields hold a value, and both labels are on screen.
      expect(find.text('myeditor'), findsOneWidget);
      expect(find.text('--goto {file}:{line}'), findsOneWidget);
      expect(find.text(l10n.settingsEditorExecutableLabel), findsOneWidget);
      expect(find.text(l10n.settingsEditorArgsTemplateLabel), findsOneWidget);
      expect(
        find.text(
          l10n.settingsEditorTemplateHelp('{file}', '{line}', '{column}'),
        ),
        findsOneWidget,
      );
      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(field.decoration?.labelText, isNull);
      }

      // The row's label is still each field's accessible name.
      final names = [
        for (final node in [
          for (final f in find.byType(TextField).evaluate())
            tester.getSemantics(find.byWidget(f.widget)),
        ])
          node.label,
      ];
      expect(names[0], contains(l10n.settingsEditorExecutableLabel));
      expect(names[1], contains(l10n.settingsEditorArgsTemplateLabel));

      // Typing into a merged row's field, with semantics on, raises nothing.
      await tester.enterText(find.byType(TextField).first, 'other-editor');
      await tester.pump();
      expect(find.text('other-editor'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}
