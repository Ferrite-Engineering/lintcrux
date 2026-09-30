// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/app.dart';
import 'package:lintcrux/core/shortcuts/action_category.dart';
import 'package:lintcrux/core/shortcuts/action_label.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_context.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_descriptor.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_descriptors.dart';
import 'package:lintcrux/core/shortcuts/shortcut_manager_widget.dart';
import 'package:lintcrux/domain/models/lintcrux_tab_payload.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/workspace/lintcrux_workspace_codec.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/eula_test_acceptance.dart';
import 'support/telemetry_test_store.dart';

/// Contract for [LintcruxAction.closeAllTabs] — the open-core
/// tab-closing capability.
///
/// The multi-project registry is Pro in every product that has one, so
/// `closeAllProjects` carries the PRO badge. `closeAllTabs` is the
/// registry-free capability that stays free: it closes every workspace
/// tab, confirms first because it is destructive, and never consults a
/// license tier. SimCrux ships the same action with the same shape.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final containersToDispose = <ProviderContainer>[];

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
    tempDir = await Directory.systemTemp.createTemp('lintcrux_close_all_');
    containersToDispose.clear();
  });

  tearDown(() async {
    for (final c in containersToDispose.reversed) {
      c.dispose();
    }
    containersToDispose.clear();
    if (tempDir.existsSync()) {
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        // Best-effort cleanup; the OS reclaims the temp dir later.
      }
    }
  });

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [
        ...telemetryDeclinedOverrides(),
        workspaceServiceProvider.overrideWithValue(
          WorkspaceService(
            codec: const LintcruxWorkspaceCodec(),
            directoryFactory: () async => tempDir,
          ),
        ),
      ],
    );
    containersToDispose.add(container);
    return container;
  }

  Future<void> seedTabs(ProviderContainer container, int count) async {
    await container.read(workspaceProvider.future);
    final notifier = container.read(workspaceProvider.notifier);
    for (var i = 0; i < count; i++) {
      await notifier.openTab(
        displayName: 'project_$i',
        payload: LintcruxTabPayload(projectPath: '/p/project_$i.lintcrux'),
      );
    }
  }

  ProviderContainer bootedContainer(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(LintcruxApp)));

  Future<void> boot(WidgetTester tester) async {
    // A seeded tab renders the full IDE layout (ViolationTable etc.); give
    // it a tall surface so the table does not overflow the default 800x600
    // and trip `takeException`.
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Inject a tempdir-backed workspace service and complete its real-disk
    // load inside runAsync, so the workspace resolves to a concrete (empty)
    // value instead of staying AsyncLoading forever under the fake clock.
    // The closeAllTabs empty-guard reads `workspaceProvider.value`, so the
    // dialog tests need a loaded workspace, not a null one.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...telemetryDeclinedOverrides(),
            // The beta-distribution wiring (`crux_updates` /
            // `crux_issue_reporter` / beta-expiry clock) is part of
            // `LintcruxApp`'s contract: the update banner mounted in
            // `MaterialApp.builder` reads `cruxUpdateConfigProvider`, which has
            // no default binding by design. A harness that mounts the app
            // widget directly rather than through `bootstrap()` has to supply
            // the same list.
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
      await bootedContainer(tester).read(workspaceProvider.future);
    });
    await tester.pumpAndSettle();
  }

  void dispatch(WidgetTester tester) {
    final manager = tester.widget<ShortcutManagerWidget>(
      find.byType(ShortcutManagerWidget),
    );
    manager.handlers[LintcruxAction.closeAllTabs]!();
  }

  /// Cancels and flushes the debounced auto-save so a mutation leaves no
  /// Timer pending at test teardown (the fake clock never fires it).
  Future<void> drainSaves(WidgetTester tester) async {
    await tester.runAsync(
      () => bootedContainer(
        tester,
      ).read(workspaceProvider.notifier).flushPendingSave(),
    );
    await tester.pump();
  }

  /// Opens one tab in the booted app so the destructive-confirm path has
  /// something to close — the handler now no-ops (no dialog) on an empty
  /// workspace, so the dialog tests must seed a tab first.
  Future<void> seedBootedTab(WidgetTester tester) async {
    final notifier = bootedContainer(tester).read(workspaceProvider.notifier);
    await tester.runAsync(
      () => notifier.openTab(
        displayName: 'seed',
        payload: const LintcruxTabPayload(projectPath: '/p/seed.lintcrux'),
      ),
    );
    await drainSaves(tester);
    await tester.pumpAndSettle();
  }

  L10N l10nOf(WidgetTester tester) =>
      L10N.of(tester.element(find.byType(Navigator).first));

  group('tier', () {
    test('is open-core — the capability is free', () {
      expect(LintcruxAction.closeAllTabs.requiredTier, LicenseTier.openCore);
    });

    test('the registry-aware variant stays Pro', () {
      // Guards the pairing: if `closeAllProjects` ever silently drops to
      // openCore, the reason `closeAllTabs` exists has evaporated.
      expect(LintcruxAction.closeAllProjects.requiredTier, LicenseTier.pro);
    });
  });

  group('reachability', () {
    // Menu / palette visibility now comes from the descriptor table, which
    // also gates enablement — closeAllTabs needs a tab to close, so these
    // assert against a context that has one.
    const withTab = LintcruxActionContext(hasOpenTab: true);

    test('appears in the menu bar', () {
      expect(
        isActionVisibleIn(
          LintcruxAction.closeAllTabs,
          LintcruxActionSurface.menu,
          withTab,
        ),
        isTrue,
      );
    });

    test('appears in the command palette when a tab is open', () {
      expect(
        paletteActionsFor(withTab),
        contains(LintcruxAction.closeAllTabs),
      );
    });

    test('is greyed out with no tab to close', () {
      const empty = LintcruxActionContext();
      expect(isActionEnabled(LintcruxAction.closeAllTabs, empty), isFalse);
      expect(
        paletteActionsFor(empty),
        isNot(contains(LintcruxAction.closeAllTabs)),
      );
    });

    test('files under the File category, beside closeAllProjects', () {
      expect(LintcruxAction.closeAllTabs.category, ActionCategory.file);
      expect(
        groupedActionsFor(
          LintcruxActionSurface.menu,
          withTab,
        )[ActionCategory.file],
        contains(LintcruxAction.closeAllTabs),
      );
    });
  });

  group('confirmation', () {
    testWidgets('mounts the dialog rather than closing immediately', (
      tester,
    ) async {
      await boot(tester);
      await seedBootedTab(tester);
      dispatch(tester);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('closeAllTabsConfirmDialog')),
        findsOneWidget,
      );
      final l10n = l10nOf(tester);
      expect(find.text(l10n.closeAllTabsConfirmTitle), findsOneWidget);
      expect(find.text(l10n.closeAllTabsConfirmBody), findsOneWidget);
    });

    testWidgets('is a silent no-op on an empty workspace (no dialog)', (
      tester,
    ) async {
      await boot(tester);
      final container = bootedContainer(tester);
      // A fresh tempdir workspace loads with no tabs.
      expect(container.read(workspaceProvider).value?.tabs, isEmpty);

      dispatch(tester);
      await tester.pumpAndSettle();

      // No confirmation prompt over an empty workspace.
      expect(find.byKey(const Key('closeAllTabsConfirmDialog')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancelling dismisses without touching the workspace', (
      tester,
    ) async {
      await boot(tester);
      await seedBootedTab(tester);
      final container = bootedContainer(tester);
      final before = container.read(workspaceProvider).value?.tabs.length;

      dispatch(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('closeAllTabsConfirmCancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('closeAllTabsConfirmDialog')), findsNothing);
      expect(container.read(workspaceProvider).value?.tabs.length, before);
      expect(tester.takeException(), isNull);
    });

    testWidgets('confirming leaves no tab open', (tester) async {
      await boot(tester);
      await seedBootedTab(tester);
      final container = bootedContainer(tester);

      dispatch(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('closeAllTabsConfirmAction')));
      await tester.pumpAndSettle();
      // The confirmed close loop mutates the workspace, scheduling a save.
      await drainSaves(tester);

      expect(find.byKey(const Key('closeAllTabsConfirmDialog')), findsNothing);
      expect(
        container.read(workspaceProvider).value?.tabs ?? const [],
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('close semantics', () {
    // Exercised against the workspace notifier directly: the action's
    // confirmed branch is a `closeTab` loop over `workspace.tabs`, and
    // that loop is what distinguishes it from `resetWorkspace`.
    test('the closeTab loop empties a populated workspace', () async {
      final container = buildContainer();
      await seedTabs(container, 3);
      final notifier = container.read(workspaceProvider.notifier);

      for (final tab in container.read(workspaceProvider).requireValue.tabs) {
        await notifier.closeTab(tab.id);
      }

      expect(container.read(workspaceProvider).requireValue.tabs, isEmpty);
    });

    test('preserves the workspace extras that resetWorkspace drops', () async {
      // The distinction that earns this action its own enum value:
      // `resetWorkspace` swaps in `Workspace.empty()` and loses the
      // ambient layout flags; closing tabs one by one keeps them.
      final container = buildContainer();
      await seedTabs(container, 2);
      final notifier = container.read(workspaceProvider.notifier);
      final seeded = container.read(workspaceProvider).requireValue;
      await notifier.replaceWith(
        seeded.copyWith(extras: const {'statisticsStripVisible': false}),
      );

      for (final tab in container.read(workspaceProvider).requireValue.tabs) {
        await notifier.closeTab(tab.id);
      }

      final afterClose = container.read(workspaceProvider).requireValue;
      expect(afterClose.tabs, isEmpty);
      expect(
        afterClose.extras['statisticsStripVisible'],
        false,
        reason: 'closing tabs must not reset the user layout',
      );

      await notifier.resetWorkspace();
      expect(
        container.read(workspaceProvider).requireValue.extras,
        isEmpty,
        reason:
            'resetWorkspace is the destructive variant — if it also kept '
            'extras the two actions would be redundant',
      );
    });
  });

  group('locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders the confirmation in ${locale.toLanguageTag()}', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Builder(
              builder: (context) {
                final l10n = L10N.of(context);
                return Column(
                  children: [
                    Text(l10n.actionCloseAllTabs),
                    Text(l10n.closeAllTabsConfirmTitle),
                    Text(l10n.closeAllTabsConfirmBody),
                    Text(l10n.closeAllTabsConfirmConfirm),
                  ],
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Every string resolves to a non-empty translation in this
        // locale — the ARB parity contract, asserted at render time.
        for (final text in tester.widgetList<Text>(find.byType(Text))) {
          expect(text.data, isNotNull);
          expect(text.data, isNotEmpty);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the action label is localized, not hardcoded', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          locale: const Locale('ja'),
          home: Builder(
            builder: (context) =>
                Text(LintcruxAction.closeAllTabs.label(L10N.of(context))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Close All Tabs'), findsNothing);
    });
  });
}
