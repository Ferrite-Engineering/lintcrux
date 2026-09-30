// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_keybindings/crux_keybindings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/shortcuts/keymap_presets.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/shortcut_bindings.dart';
import 'package:lintcrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:lintcrux/features/settings/widgets/shortcuts_settings_section.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> freshPrefs() async {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }

  Widget wrap(SharedPreferences prefs, {Locale locale = const Locale('en')}) =>
      ProviderScope(
        overrides: [
          shortcutBindingsStoreProvider.overrideWithValue(
            KeyBindingsStore<LintcruxAction>(
              codec: lintCruxKeymapCodec,
              prefsOverride: prefs,
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          locale: locale,
          home: const Scaffold(body: ShortcutsSettingsSection()),
        ),
      );

  /// Like [wrap] but injects the import file picker so the test can feed
  /// the section an arbitrary keymap document without the platform plugin.
  Widget wrapWithImport(
    SharedPreferences prefs,
    Future<File?> Function() pickImportFile, {
    Locale locale = const Locale('en'),
  }) => ProviderScope(
    overrides: [
      shortcutBindingsStoreProvider.overrideWithValue(
        KeyBindingsStore<LintcruxAction>(
          codec: lintCruxKeymapCodec,
          prefsOverride: prefs,
        ),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      locale: locale,
      home: Scaffold(
        body: ShortcutsSettingsSection(pickImportFile: pickImportFile),
      ),
    ),
  );

  /// Writes [contents] to a temp `.crux-keymap.json` up front and returns
  /// a picker that hands the file back.
  ///
  /// Written synchronously: `testWidgets` runs under fake async, where an
  /// awaited real-IO future never completes.
  Future<File?> Function() keymapFileWith(String contents) {
    final dir = Directory.systemTemp.createTempSync('lintcrux_keymap_');
    addTearDown(() {
      try {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows can still hold a handle on the file the import just read,
        // which makes the delete throw errno 32. A leaked temp directory is
        // not worth failing an otherwise green test over.
      }
    });
    final file = File('${dir.path}/x.crux-keymap.json')
      ..writeAsStringSync(contents);
    return () async => file;
  }

  /// Taps Import… and returns the SnackBar text the section showed.
  ///
  /// The tap is driven inside [WidgetTester.runAsync] because the import
  /// path does real file IO, which fake async never completes. The
  /// follow-up pumps are discrete rather than `pumpAndSettle` so they do
  /// not advance past the SnackBar's auto-dismiss timer.
  Future<void> tapImport(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Import…'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Import…'), warnIfMissed: false);
      // Let the picker + readAsString + decode start on the real loop.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    // A single fixed sleep is a race: on a loaded CI runner the real-loop
    // file read and decode outlast it and the SnackBar never arrives. Hand
    // the import more real time in slices, pumping between them, until it
    // has something to show. `tester.pump()` with no duration advances the
    // fake clock by zero, so this cannot walk past the auto-dismiss timer.
    for (var i = 0; i < 100 && find.byType(SnackBar).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }

    await tester.pump(const Duration(milliseconds: 400));
  }

  group('keymap import failure messages', () {
    testWidgets(
      'a keymap from a newer LintCrux gets the update-your-build message, '
      'not "invalid file"',
      (tester) async {
        // A forward-version envelope is a well-formed file this build is
        // simply too old to read. Reporting it as invalid would send the
        // user chasing a corruption that does not exist.
        final pick = keymapFileWith(
          jsonEncode(<String, Object?>{
            'version': kKeymapVersion + 1,
            'bindings': <String, Object?>{},
          }),
        );
        await tester.pumpWidget(
          wrapWithImport(await freshPrefs(), pick),
        );
        await tester.pumpAndSettle();

        await tapImport(tester);

        final l10n = L10N.of(
          tester.element(find.byType(ShortcutsSettingsSection)),
        );
        expect(
          find.text(l10n.settingsShortcutImportFailureNewerVersion),
          findsOneWidget,
        );
      },
    );

    testWidgets('a genuinely malformed keymap still gets the generic '
        'failure message', (tester) async {
      final pick = keymapFileWith('this is not json at all');
      await tester.pumpWidget(wrapWithImport(await freshPrefs(), pick));
      await tester.pumpAndSettle();

      await tapImport(tester);

      final l10n = L10N.of(
        tester.element(find.byType(ShortcutsSettingsSection)),
      );
      expect(
        find.text(l10n.settingsShortcutImportFailureNewerVersion),
        findsNothing,
        reason: 'a corrupt file is not a version problem',
      );
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(ShortcutsSettingsSection)),
        listen: false,
      );

  testWidgets('renders the editor rows and controls', (tester) async {
    await tester.pumpWidget(wrap(await freshPrefs()));
    await tester.pumpAndSettle();

    expect(find.byType(KeyBindingRow), findsWidgets);
    expect(find.text('Import…'), findsOneWidget);
    expect(find.text('Export…'), findsOneWidget);
    expect(find.text('Reset all'), findsOneWidget);
  });

  testWidgets(
    "conflict warning is asymmetric: only the shadowed row says it won't "
    'fire (issue #36 bug 1)',
    (tester) async {
      await tester.pumpWidget(wrap(await freshPrefs()));
      await tester.pumpAndSettle();

      // Remap cancelRun onto runAllEngines' chord: cancelRun is the customized
      // interloper (wins); runAllEngines is the default owner (shadowed).
      final runChord = containerOf(
        tester,
      ).read(shortcutBindingsProvider)[LintcruxAction.runAllEngines]!;
      containerOf(tester)
          .read(shortcutBindingsProvider.notifier)
          .setBinding(LintcruxAction.cancelRun, runChord);
      await tester.pump();

      expect(find.textContaining('shadowed by'), findsOneWidget);
      expect(find.textContaining('Takes precedence over'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsWidgets);
    },
  );

  testWidgets('conflict summary banner shows the count (issue #36 bug 2)', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(await freshPrefs()));
    await tester.pumpAndSettle();

    expect(find.textContaining('needs attention'), findsNothing);

    final runChord = containerOf(
      tester,
    ).read(shortcutBindingsProvider)[LintcruxAction.runAllEngines]!;
    containerOf(tester)
        .read(shortcutBindingsProvider.notifier)
        .setBinding(LintcruxAction.cancelRun, runChord);
    await tester.pump();

    expect(find.text('1 shortcut conflict needs attention'), findsOneWidget);
  });

  testWidgets('preset dropdown defaults to LintCrux (Default)', (tester) async {
    await tester.pumpWidget(wrap(await freshPrefs()));
    await tester.pumpAndSettle();

    expect(find.text('Preset'), findsOneWidget);
    expect(find.text('LintCrux (Default)'), findsOneWidget);
    expect(find.text('Custom'), findsNothing);
  });

  testWidgets('preset dropdown shows Custom after a hand edit', (tester) async {
    await tester.pumpWidget(wrap(await freshPrefs()));
    await tester.pumpAndSettle();

    containerOf(tester)
        .read(shortcutBindingsProvider.notifier)
        .setBinding(
          LintcruxAction.focusSearch,
          const SingleActivator(LogicalKeyboardKey.keyJ, control: true),
        );
    await tester.pump();

    expect(find.text('Custom'), findsOneWidget);
  });

  testWidgets('selecting the LintCrux preset restores the defaults wholesale', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(await freshPrefs()));
    await tester.pumpAndSettle();

    final notifier = containerOf(tester).read(shortcutBindingsProvider.notifier)
      ..setBinding(
        LintcruxAction.focusSearch,
        const SingleActivator(LogicalKeyboardKey.keyJ, control: true),
      );
    await tester.pump();
    expect(find.text('Custom'), findsOneWidget);

    // Open the dropdown (showing the "Custom" hint) and pick the preset.
    // Tap the button widget, not the hint Text: the hint is rendered inside
    // the button's IndexedStack and its own center may not hit-test.
    await tester.tap(find.byType(DropdownButton<KeymapPreset>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LintCrux (Default)').last);
    await tester.pumpAndSettle();

    expect(notifier.currentDiffs(), isEmpty);
    expect(find.text('LintCrux (Default)'), findsOneWidget);
    expect(find.text('Custom'), findsNothing);
  });

  group('locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders without exceptions in $locale', (tester) async {
        await tester.pumpWidget(wrap(await freshPrefs(), locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(KeyBindingRow), findsWidgets);
      });
    }
  });
}
