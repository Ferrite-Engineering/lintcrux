// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/app.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/shortcut_manager_widget.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/eula_test_acceptance.dart';
import 'support/telemetry_test_store.dart';

/// Destructive-action confirmation contract for
/// [LintcruxAction.resetWorkspace] and [LintcruxAction.newWorkspace].
///
/// Both enum members document "empty the current workspace after a single
/// confirmation dialog". Both close every open tab, so activating either
/// from the menu bar or command palette — neither of which has an undo —
/// must route through the dialog first.
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
    tempDir = await Directory.systemTemp.createTemp('lintcrux_reset_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> boot(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        // See the note in `test/widget_test.dart`: mounting `LintcruxApp`
        // outside `bootstrap()` still has to supply the beta-distribution
        // overrides.
        overrides: [
          ...telemetryDeclinedOverrides(),
          ...lintcruxPhase5Overrides(),
          eulaAcceptedOverride(),
        ],
        child: const LintcruxApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  void dispatch(WidgetTester tester, LintcruxAction action) {
    final manager = tester.widget<ShortcutManagerWidget>(
      find.byType(ShortcutManagerWidget),
    );
    manager.handlers[action]!();
  }

  L10N l10nOf(WidgetTester tester) =>
      L10N.of(tester.element(find.byType(Navigator).first));

  final destructiveActions = <LintcruxAction>[
    LintcruxAction.resetWorkspace,
    LintcruxAction.newWorkspace,
  ];

  for (final action in destructiveActions) {
    group(action.name, () {
      testWidgets('mounts the confirmation dialog rather than resetting', (
        tester,
      ) async {
        await boot(tester);
        dispatch(tester, action);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('workspaceResetConfirmDialog')),
          findsOneWidget,
          reason:
              '${action.name} destroyed the workspace with no confirmation, '
              'contradicting its enum contract.',
        );
        final l10n = l10nOf(tester);
        expect(find.text(l10n.workspaceResetConfirmTitle), findsOneWidget);
        expect(find.text(l10n.workspaceResetConfirmBody), findsOneWidget);
      });

      testWidgets('cancelling leaves the workspace untouched', (tester) async {
        await boot(tester);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(LintcruxApp)),
        );
        final before = container.read(workspaceProvider).value;

        dispatch(tester, action);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('workspaceResetConfirmCancel')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('workspaceResetConfirmDialog')),
          findsNothing,
        );
        expect(
          container.read(workspaceProvider).value?.tabs.length,
          before?.tabs.length,
          reason: 'dismissing the confirmation must not mutate the workspace',
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('confirming performs the reset', (tester) async {
        await boot(tester);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(LintcruxApp)),
        );

        dispatch(tester, action);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('workspaceResetConfirmAction')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('workspaceResetConfirmDialog')),
          findsNothing,
        );
        // A bare boot may not have materialized a workspace value yet;
        // either way, no tab may survive the confirmed reset.
        expect(
          container.read(workspaceProvider).value?.tabs ?? const [],
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      });
    });
  }
}
