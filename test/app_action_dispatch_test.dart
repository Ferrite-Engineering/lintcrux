// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_about_dialog/crux_about_dialog.dart';
import 'package:crux_command_palette/crux_command_palette.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/app.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/shortcut_manager_widget.dart';
import 'package:lintcrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:lintcrux/features/diagnostics/widgets/app_diagnostics_dialog.dart';
import 'package:lintcrux/features/diagnostics/widgets/tab_diagnostics_drawer.dart';
import 'package:lintcrux/features/project/providers/project_picker_provider.dart';
import 'package:lintcrux/features/project/services/project_picker.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/plugins/baseline_comparison_opener_provider.dart';
import 'package:lintcrux/plugins/bookmark_panel_opener_provider.dart';
import 'package:lintcrux/plugins/filter_preset_manager_opener_provider.dart';
import 'package:lintcrux/plugins/pro_action_openers.dart';
import 'package:lintcrux/plugins/pro_opener.dart';
import 'package:lintcrux/plugins/save_filter_preset_opener_provider.dart';
import 'package:lintcrux/plugins/waiver_review_opener_provider.dart';
import 'package:lintcrux/services/workspace/lintcrux_workspace_codec.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/telemetry_test_store.dart';

/// Table-driven coverage for `_dispatchPaletteAction` in `lib/app.dart` —
/// the single router behind all three action surfaces (keyboard shortcut,
/// platform menu bar, command palette). Each row boots the real
/// [LintcruxApp], fires one [LintcruxAction] through the exact closure the
/// shortcut surface registers (the [ShortcutManagerWidget.handlers] map),
/// and asserts the expected observable: the right picker method, opener
/// provider, snackbar, dialog, or state change. The Pro repo's action
/// openers hang off the opener rows, so this net protects both products.
///
/// A completeness test pins the table to `LintcruxAction.values`: adding an
/// enum member without a dispatch expectation fails here by name.
void main() {
  late Directory tempDir;
  late _RecordingPicker picker;
  late Map<String, int> openerCalls;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // The About flow awaits PackageInfo before mounting its dialog;
    // without mock values the platform-channel future never resolves.
    PackageInfo.setMockInitialValues(
      appName: 'lintcrux',
      packageName: 'com.ferrite.lintcrux',
      version: '0.0.0',
      buildNumber: '0',
      buildSignature: '',
    );
    tempDir = await Directory.systemTemp.createTemp('lintcrux_dispatch_');
    picker = _RecordingPicker();
    openerCalls = <String, int>{};
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Override spy(
    String name,
    Provider<ProActionOpener?> provider,
  ) => provider.overrideWithValue((_) {
    openerCalls[name] = (openerCalls[name] ?? 0) + 1;
  });

  Future<void> boot(
    WidgetTester tester, {
    List<Override> extraOverrides = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...telemetryDeclinedOverrides(),
          ...extraOverrides,
          // The beta-distribution wiring (`crux_updates` /
          // `crux_issue_reporter` / beta-expiry clock) is part of
          // `LintcruxApp`'s contract: the update banner mounted in
          // `MaterialApp.builder` reads `cruxUpdateConfigProvider`, which has
          // no default binding by design. A harness that mounts the app widget
          // directly rather than through `bootstrap()` has to supply the same
          // list.
          ...lintcruxPhase5Overrides(),
          workspaceServiceProvider.overrideWithValue(
            WorkspaceService(
              codec: const LintcruxWorkspaceCodec(),
              directoryFactory: () async => tempDir,
            ),
          ),
          projectPickerProvider.overrideWithValue(picker),
          // Dedicated Pro-surface opener seams.
          spy('waiverReview', waiverReviewOpenerProvider),
          spy('baselineComparison', baselineComparisonOpenerProvider),
          spy('bookmarkPanel', bookmarkPanelOpenerProvider),
          spy('filterPresetManager', filterPresetManagerOpenerProvider),
          spy('saveFilterPreset', saveFilterPresetOpenerProvider),
          // Post-Phase-4 batch opener seams.
          spy('setBaseline', setBaselineOpenerProvider),
          spy('clearBaseline', clearBaselineOpenerProvider),
          spy('toggleBookmark', toggleBookmarkOpenerProvider),
          spy('runVeribleDryRun', runVeribleDryRunOpenerProvider),
          spy('applyVeribleFixes', applyVeribleFixesOpenerProvider),
          spy('configureVeribleBinary', configureVeribleBinaryOpenerProvider),
          spy('clearLintCache', clearLintCacheOpenerProvider),
          spy('openLintCacheStats', openLintCacheStatsOpenerProvider),
          spy(
            'forceLintRunWithoutCache',
            forceLintRunWithoutCacheOpenerProvider,
          ),
          spy('showRuleTrendChart', showRuleTrendChartOpenerProvider),
          spy(
            'showSeverityClassDriftChart',
            showSeverityClassDriftChartOpenerProvider,
          ),
          spy('showProjectTrendChart', showProjectTrendChartOpenerProvider),
          spy('showCalendarHeatmap', showCalendarHeatmapOpenerProvider),
          spy('configureTrendRetention', configureTrendRetentionOpenerProvider),
          spy('pinActiveProject', pinActiveProjectOpenerProvider),
          spy('closeAllProjects', closeAllProjectsOpenerProvider),
          spy('switchProject', switchProjectOpenerProvider),
          spy('reopenRecentProject', reopenRecentProjectOpenerProvider),
          spy('searchAcrossProjects', searchAcrossProjectsOpenerProvider),
        ],
        child: const LintcruxApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Fires [action] through the exact dispatch closure the shortcut
  /// surface registers — the same `_dispatchPaletteAction` the menu bar
  /// and command palette call.
  void dispatch(WidgetTester tester, LintcruxAction action) {
    final manager = tester.widget<ShortcutManagerWidget>(
      find.byType(ShortcutManagerWidget),
    );
    final handler = manager.handlers[action];
    expect(
      handler,
      isNotNull,
      reason:
          'every LintcruxAction must have a ShortcutManagerWidget handler '
          '(app.dart registers the full enum)',
    );
    handler!();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
  }

  L10N l10nOf(WidgetTester tester) =>
      L10N.of(tester.element(find.byType(Navigator).first));

  ProviderContainer rootContainer(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(LintcruxApp)));

  // ── Expectation builders ─────────────────────────────────────────

  _DispatchCase pickerCall(String method) => _DispatchCase(
    'invokes picker.$method',
    (tester) async {
      expect(picker.calls, contains(method));
    },
  );

  _DispatchCase openerFires(String name) => _DispatchCase(
    'fires the $name opener seam',
    (tester) async {
      expect(openerCalls[name], 1, reason: 'opener "$name" must fire once');
    },
  );

  _DispatchCase snack(String Function(L10N l10n) text) => _DispatchCase(
    'surfaces the expected snackbar',
    (tester) async {
      expect(find.text(text(l10nOf(tester))), findsOneWidget);
    },
  );

  _DispatchCase mountsDialog(Type type) => _DispatchCase(
    'mounts $type',
    (tester) async {
      expect(find.byType(type), findsOneWidget);
    },
  );

  // With an empty workspace there is nothing for these actions to act
  // on; the contract is a silent no-op — no crash, no stray feedback.
  final noopOnEmptyWorkspace = _DispatchCase(
    'silently no-ops on an empty workspace',
    (tester) async {
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  final table = <LintcruxAction, _DispatchCase>{
    // ── File ─────────────────────────────────────────────────────
    LintcruxAction.openProject: pickerCall('pickProjectFile'),
    LintcruxAction.openSources: snack((l) => l.openSourcesNoActiveProject),
    LintcruxAction.importVivadoFilelist: pickerCall('pickFilelistFile'),
    LintcruxAction.importEdam: pickerCall('pickEdamFile'),
    LintcruxAction.resetWorkspace: noopOnEmptyWorkspace,
    LintcruxAction.saveSession: snack((l) => l.exportSessionNoActiveTab),
    LintcruxAction.openSession: pickerCall('pickSessionFile'),
    LintcruxAction.importSarif: pickerCall('pickSarifFile'),
    LintcruxAction.newWorkspace: noopOnEmptyWorkspace,
    LintcruxAction.saveWorkspaceAs: pickerCall('pickSaveWorkspaceFile'),
    LintcruxAction.openWorkspace: pickerCall('pickWorkspaceFile'),
    LintcruxAction.newTab: pickerCall('pickSaveProjectFile'),
    LintcruxAction.closeTab: noopOnEmptyWorkspace,
    LintcruxAction.closeActiveProject: noopOnEmptyWorkspace,
    // Destructive with no undo, so it confirms before touching the
    // workspace — but only when there is something to close. This harness
    // boots an empty workspace, so the empty-workspace guard makes it a
    // silent no-op: no confirmation dialog. (The populated-workspace dialog
    // path is covered by app_close_all_tabs_test.dart.)
    LintcruxAction.closeAllTabs: _DispatchCase(
      'silently no-ops (no confirmation) on an empty workspace',
      (tester) async {
        expect(
          find.byKey(const Key('closeAllTabsConfirmDialog')),
          findsNothing,
        );
      },
    ),
    // ── App ──────────────────────────────────────────────────────
    // openAdaptive mounts the suite-shared shell (crux_settings_ui);
    // SettingsScreen remains only for the /settings deep-link route.
    LintcruxAction.openSettings: mountsDialog(CruxSettingsRouteShell),
    // ── Run ──────────────────────────────────────────────────────
    LintcruxAction.runAllEngines: snack((l) => l.runEnginesNoActiveProject),
    LintcruxAction.cancelRun: snack((l) => l.cancelRunNoActiveRun),
    // ── View ─────────────────────────────────────────────────────
    LintcruxAction.toggleTheme: _DispatchCase(
      'flips the rendered brightness',
      (tester) async {
        // The before-value is captured by the test body below via the
        // closure; asserting inequality happens there.
      },
    ),
    LintcruxAction.splitPaneRight: _DispatchCase(
      'splits the workspace into two panes',
      (tester) async {
        final workspace = rootContainer(
          tester,
        ).read(workspaceProvider).value;
        expect(workspace?.panes.length, 2);
      },
    ),
    LintcruxAction.closePane: noopOnEmptyWorkspace,
    LintcruxAction.focusOtherPane: noopOnEmptyWorkspace,
    LintcruxAction.moveTabToOtherPane: noopOnEmptyWorkspace,
    LintcruxAction.nextTab: noopOnEmptyWorkspace,
    LintcruxAction.previousTab: noopOnEmptyWorkspace,
    // ── Search / palette ────────────────────────────────────────
    // CommandPaletteDialog.show delegates to the shared CommandPalette
    // widget, so that is what lands in the tree.
    LintcruxAction.openCommandPalette: mountsDialog(
      CommandPalette<LintcruxAction>,
    ),
    LintcruxAction.focusSearch: noopOnEmptyWorkspace,
    LintcruxAction.searchAcrossProjects: openerFires('searchAcrossProjects'),
    // ── Tools / Help ────────────────────────────────────────────
    LintcruxAction.exportSarif: snack((l) => l.runEnginesNoActiveProject),
    LintcruxAction.exportJson: snack((l) => l.runEnginesNoActiveProject),
    LintcruxAction.exportCsv: snack((l) => l.runEnginesNoActiveProject),
    LintcruxAction.exportHtml: snack((l) => l.runEnginesNoActiveProject),
    // The overlay drawer follows WaveCrux's no-tabs auto-dismiss: with an
    // empty workspace it closes itself before it ever renders, so nothing
    // mounts and no feedback appears. (The populated-workspace path is
    // covered by tab_diagnostics_drawer_test.dart's `.open` group.)
    LintcruxAction.openTabDiagnostics: _DispatchCase(
      'auto-dismisses on an empty workspace (WaveCrux parity)',
      (tester) async {
        expect(find.byType(TabDiagnosticsDrawer), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
      },
    ),
    LintcruxAction.openAppDiagnostics: mountsDialog(AppDiagnosticsDialog),
    // LintcruxAboutDialog.openAdaptive awaits the build-info future
    // before mounting the shared CruxAboutDialog (dialog on desktop,
    // pushed route on mobile — the widget type is the same either way).
    LintcruxAction.openAbout: mountsDialog(CruxAboutDialog),
    // The cross-probe action now toggles the docked side-panel
    // (`crossProbeVisible`) rather than mounting a modal dialog.
    LintcruxAction.openCrossProbePanel: _DispatchCase(
      'toggles the docked cross-probe panel visible',
      (tester) async {
        expect(
          rootContainer(tester).read(panelLayoutProvider).crossProbeVisible,
          isTrue,
        );
      },
    ),
    // Open-core aliases dispatch through the same Pro opener seams as
    // their Phase-4 counterparts.
    LintcruxAction.saveFilterPreset: openerFires('saveFilterPreset'),
    LintcruxAction.manageFilterPresets: openerFires('filterPresetManager'),
    // ── Pro-tier opener seams ─────────────────────────
    LintcruxAction.openWaiverReview: openerFires('waiverReview'),
    LintcruxAction.setBaseline: openerFires('setBaseline'),
    LintcruxAction.clearBaseline: openerFires('clearBaseline'),
    LintcruxAction.openBaselineComparison: openerFires('baselineComparison'),
    LintcruxAction.showRuleTrendChart: openerFires('showRuleTrendChart'),
    LintcruxAction.showSeverityClassDriftChart: openerFires(
      'showSeverityClassDriftChart',
    ),
    LintcruxAction.showProjectTrendChart: openerFires('showProjectTrendChart'),
    LintcruxAction.showCalendarHeatmap: openerFires('showCalendarHeatmap'),
    LintcruxAction.configureTrendRetention: openerFires(
      'configureTrendRetention',
    ),
    LintcruxAction.openBookmarksManager: openerFires('bookmarkPanel'),
    LintcruxAction.toggleBookmarkForCurrentViolation: openerFires(
      'toggleBookmark',
    ),
    LintcruxAction.runVeribleDryRun: openerFires('runVeribleDryRun'),
    LintcruxAction.applyVeribleFixes: openerFires('applyVeribleFixes'),
    LintcruxAction.configureVeribleBinary: openerFires(
      'configureVeribleBinary',
    ),
    LintcruxAction.clearLintCache: openerFires('clearLintCache'),
    LintcruxAction.openLintCacheStats: openerFires('openLintCacheStats'),
    LintcruxAction.forceLintRunWithoutCache: openerFires(
      'forceLintRunWithoutCache',
    ),
    // ── Multi-project (Pro ops) ─────────────────────────────────
    // All four route through Pro openers (the switcher, recents and
    // cross-project search come from the shared crux_projects_ui).
    LintcruxAction.switchProject: openerFires('switchProject'),
    LintcruxAction.reopenRecentProject: openerFires('reopenRecentProject'),
    LintcruxAction.pinActiveProject: openerFires('pinActiveProject'),
    LintcruxAction.closeAllProjects: openerFires('closeAllProjects'),
    // ── Beta infrastructure (open-core) ─────────────────────────
    // The manual check always runs — it ignores the Settings → General
    // auto-check toggle — and reports its outcome as a toast. Under the
    // test harness's default (mobile) target platform the service is the
    // no-op stand-in, so the outcome is "already current" against the
    // mocked PackageInfo version. The available / error / suppressed-auto
    // states are covered in
    // `test/features/update/update_status_wiring_test.dart`.
    LintcruxAction.checkForUpdates: snack(
      (l) => l.updateCheckUpToDate('0.0.0'),
    ),
  };

  const excluded = <LintcruxAction>{
    // `quit` calls exit(0) — untestable in-process by design.
    LintcruxAction.quit,
    // `submitIssue` awaits the engine-version probe — one subprocess per
    // registered engine — before it mounts anything, so it cannot resolve
    // inside `pump()` and should not be spawning processes from this
    // table-driven suite at all. Its wiring is covered structurally in
    // `test/app_phase5_wiring_test.dart` (config, session contributor,
    // screenshot boundary) and behaviorally in
    // `test/features/issue_reporter/` and
    // `test/features/engine_config/providers/`.
    LintcruxAction.submitIssue,
    // `openDocumentation` hands a URL to the platform browser through the
    // `lintcruxLaunchUrl` seam; there is no in-app surface for this table to
    // observe. The seam itself is what a test would swap.
    LintcruxAction.openDocumentation,
  };

  test('every LintcruxAction has a dispatch expectation (or is excluded)', () {
    expect(
      table.keys.toSet().union(excluded),
      LintcruxAction.values.toSet(),
      reason:
          'new LintcruxAction members need a row in this table so their '
          '_dispatchPaletteAction case is pinned across all three surfaces',
    );
    expect(table.keys.toSet().intersection(excluded), isEmpty);
  });

  // The release-build diagnostics gate. Debug test runs force diagnostics
  // on, so the table above exercises the open path; these take the release
  // path with the Settings switch in its default (off) position.
  for (final action in const [
    LintcruxAction.openTabDiagnostics,
    LintcruxAction.openAppDiagnostics,
  ]) {
    testWidgets(
      '${action.name} — in a release build with diagnostics off, opens '
      'nothing and says where the switch is',
      (tester) async {
        await boot(
          tester,
          extraOverrides: [
            diagnosticsForcedByBuildModeProvider.overrideWithValue(false),
          ],
        );
        dispatch(tester, action);
        await settle(tester);
        final l10n = l10nOf(tester);
        expect(
          find.text(l10n.diagnosticsDisabledSnack(l10n.settingsGeneralSection)),
          findsOneWidget,
        );
        expect(find.byType(AppDiagnosticsDialog), findsNothing);
        expect(find.byType(TabDiagnosticsDrawer), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'openAppDiagnostics — in a release build with diagnostics turned on in '
    'Settings, mounts the dialog',
    (tester) async {
      await boot(
        tester,
        extraOverrides: [
          diagnosticsForcedByBuildModeProvider.overrideWithValue(false),
        ],
      );
      rootContainer(
        tester,
      ).read(appSettingsProvider.notifier).setDiagnosticsEnabled(enabled: true);
      dispatch(tester, LintcruxAction.openAppDiagnostics);
      await settle(tester);
      expect(find.byType(AppDiagnosticsDialog), findsOneWidget);

      // Turning the switch off while the dialog is open closes it.
      rootContainer(
            tester,
          )
          .read(appSettingsProvider.notifier)
          .setDiagnosticsEnabled(enabled: false);
      await tester.pumpAndSettle();
      expect(find.byType(AppDiagnosticsDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final entry in table.entries) {
    final action = entry.key;
    final dispatchCase = entry.value;
    testWidgets('${action.name} — ${dispatchCase.expectation}', (
      tester,
    ) async {
      await boot(tester);
      // What the user sees, not a stored flag: the app theme mode MaterialApp
      // actually renders with.
      ThemeMode renderedMode() =>
          tester
              .widget<MaterialApp>(find.byType(MaterialApp).first)
              .themeMode ??
          ThemeMode.system;
      final themeBefore = renderedMode();
      dispatch(tester, action);
      await settle(tester);
      await dispatchCase.verify(tester);
      if (action == LintcruxAction.toggleTheme) {
        expect(renderedMode(), isNot(themeBefore));
      }
      expect(tester.takeException(), isNull);
    });
  }
}

/// One row of the dispatch table: a human-readable expectation (baked
/// into the test name) plus its assertion.
class _DispatchCase {
  const _DispatchCase(this.expectation, this.verify);

  final String expectation;
  final Future<void> Function(WidgetTester tester) verify;
}

/// [ProjectPicker] double that records which picker entry point each
/// dispatch reached and cancels every dialog (returns null / empty), so
/// the flows end deterministically after the pick.
class _RecordingPicker implements ProjectPicker {
  final List<String> calls = <String>[];

  @override
  Future<String?> pickProjectFile({
    required String confirmButtonText,
    required String typeLabel,
  }) async {
    calls.add('pickProjectFile');
    return null;
  }

  @override
  Future<List<String>> pickSourceFiles({
    required String confirmButtonText,
    required String typeLabel,
  }) async {
    calls.add('pickSourceFiles');
    return const [];
  }

  @override
  Future<String?> pickSarifFile({
    required String confirmButtonText,
    required String typeLabel,
  }) async {
    calls.add('pickSarifFile');
    return null;
  }

  @override
  Future<String?> pickFilelistFile({
    required String confirmButtonText,
    required String typeLabel,
  }) async {
    calls.add('pickFilelistFile');
    return null;
  }

  @override
  Future<String?> pickEdamFile({
    required String confirmButtonText,
    required String typeLabel,
  }) async {
    calls.add('pickEdamFile');
    return null;
  }

  @override
  Future<String?> pickSessionFile({
    required String confirmButtonText,
    required String typeLabel,
  }) async {
    calls.add('pickSessionFile');
    return null;
  }

  @override
  Future<String?> pickWorkspaceFile({
    required String confirmButtonText,
    required String typeLabel,
  }) async {
    calls.add('pickWorkspaceFile');
    return null;
  }

  @override
  Future<String?> pickSaveProjectFile({
    required String confirmButtonText,
    required String typeLabel,
    String? defaultFileName,
  }) async {
    calls.add('pickSaveProjectFile');
    return null;
  }

  @override
  Future<String?> pickSaveExportFile({
    required String confirmButtonText,
    required String extension,
    required String label,
    String? defaultFileName,
  }) async {
    calls.add('pickSaveExportFile');
    return null;
  }

  @override
  Future<String?> pickSaveWorkspaceFile({
    required String confirmButtonText,
    required String typeLabel,
    String? defaultFileName,
  }) async {
    calls.add('pickSaveWorkspaceFile');
    return null;
  }

  @override
  Future<String?> pickExportSessionFile({
    required String confirmButtonText,
    required String typeLabel,
    String? defaultFileName,
  }) async {
    calls.add('pickExportSessionFile');
    return null;
  }
}
