// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_command_palette/crux_command_palette.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/app.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/domain/models/lintcrux_tab_payload.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/services/remote/cxp/lintcrux_cxp_binding.dart';
import 'package:lintcrux/services/workspace/lintcrux_workspace_codec.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/eula_test_acceptance.dart';
import 'support/telemetry_test_store.dart';

/// Closing the command palette must leave keyboard focus somewhere the
/// app-level shortcuts can hear it, so a chord pressed straight afterwards
/// still fires. Toggle Theme (Cmd+Shift+K) used to do nothing after the palette
/// was dismissed until the user clicked into the window.
void main() {
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      ...kEulaAcceptedPrefs,
    });
    PackageInfo.setMockInitialValues(
      appName: 'lintcrux',
      packageName: 'com.ferrite.lintcrux',
      version: '0.0.0',
      buildNumber: '0',
      buildSignature: '',
    );
    tempDir = await Directory.systemTemp.createTemp('lintcrux_palette_focus_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...telemetryDeclinedOverrides(),
          cruxCxpProductBindingProvider.overrideWithValue(kLintcruxCxpBinding),
          ...lintcruxPhase5Overrides(),
          eulaAcceptedOverride(),
          workspaceServiceProvider.overrideWithValue(
            WorkspaceService(
              codec: const LintcruxWorkspaceCodec(),
              directoryFactory: () async => tempDir,
            ),
          ),
        ],
        child: const LintcruxApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openProjectTab(WidgetTester tester) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LintcruxApp)),
    );
    await tester.runAsync(() async {
      await container.read(workspaceProvider.future);
      await container
          .read(workspaceProvider.notifier)
          .openTab(
            displayName: 'project',
            payload: const LintcruxTabPayload(
              projectPath: '/p/project.lintcrux',
            ),
          );
    });
    await tester.pumpAndSettle();
  }

  ThemeMode renderedMode(WidgetTester tester) =>
      tester.widget<MaterialApp>(find.byType(MaterialApp).first).themeMode ??
      ThemeMode.system;

  Future<void> chord(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
  }

  final palette = find.byType(CommandPalette<LintcruxAction>);

  /// Opens the palette with its chord, lets [closeIt] dismiss it, and checks
  /// that Toggle Theme still answers its chord.
  Future<void> expectThemeChordSurvives(
    WidgetTester tester, {
    required Future<void> Function() closeIt,
  }) async {
    final initial = renderedMode(tester);
    await chord(tester, LogicalKeyboardKey.keyK);
    final afterFirst = renderedMode(tester);
    expect(
      afterFirst,
      isNot(initial),
      reason: 'the chord works before the palette was ever opened',
    );

    await chord(tester, LogicalKeyboardKey.keyP);
    expect(palette, findsOneWidget, reason: 'Cmd+Shift+P opens the palette');

    await closeIt();
    await tester.pumpAndSettle();
    expect(palette, findsNothing, reason: 'the palette closed');

    await chord(tester, LogicalKeyboardKey.keyK);
    expect(
      renderedMode(tester),
      isNot(afterFirst),
      reason:
          'focus must be somewhere under the app after the palette closes, '
          'so app-level shortcuts keep firing',
    );
  }

  for (final withTab in [false, true]) {
    final where = withTab
        ? 'with a project tab open'
        : 'on the empty workspace';

    testWidgets(
      'Cmd+Shift+K toggles the theme after Escape closes the palette, $where',
      (tester) async {
        await boot(tester);
        if (withTab) await openProjectTab(tester);
        await expectThemeChordSurvives(
          tester,
          closeIt: () => tester.sendKeyEvent(LogicalKeyboardKey.escape),
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      'Cmd+Shift+K toggles the theme after the palette closes with focus '
      'dropped to the window root, $where',
      (tester) async {
        await boot(tester);
        if (withTab) await openProjectTab(tester);
        await expectThemeChordSurvives(
          tester,
          closeIt: () async {
            // What the platform can leave behind while a modal is up: nothing
            // under the app holds focus any more, so the route's removal has
            // no previous child to fall back to. Walk focus up to the root.
            for (var i = 0; i < 6; i++) {
              FocusManager.instance.primaryFocus?.unfocus();
              await tester.pump();
            }
            expect(
              FocusManager.instance.primaryFocus,
              FocusManager.instance.rootScope,
            );
            // Close by clicking the scrim, which needs no focused node.
            await tester.tapAt(const Offset(5, 2100));
          },
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'focus goes back to the field that held it before the palette opened',
    (tester) async {
      await boot(tester);
      await openProjectTab(tester);
      final field = find.byType(TextField).first;
      await tester.tap(field);
      await tester.pump();
      final before = FocusManager.instance.primaryFocus;
      expect(before, isNotNull);

      await chord(tester, LogicalKeyboardKey.keyP);
      expect(palette, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus, before);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
