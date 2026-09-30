// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/app.dart';
import 'package:lintcrux/core/shortcuts/action_label.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/shortcut_manager_widget.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/plugins/baseline_comparison_opener_provider.dart';
import 'package:lintcrux/plugins/bookmark_panel_opener_provider.dart';
import 'package:lintcrux/plugins/filter_preset_manager_opener_provider.dart';
import 'package:lintcrux/plugins/pro_action_openers.dart';
import 'package:lintcrux/plugins/pro_opener.dart';
import 'package:lintcrux/plugins/save_filter_preset_opener_provider.dart';
import 'package:lintcrux/plugins/waiver_review_opener_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/telemetry_test_store.dart';

/// Open-core feedback contract for the Pro action-opener seams.
///
/// In an open-core build every opener provider is null. Activating the
/// corresponding menu / palette entry must tell the user *something* —
/// a Pro-badged entry that does nothing when clicked is indistinguishable
/// from a bug, and these entries stay visible for discoverability rather
/// than being hidden (`kMenuHiddenActions` is deliberately empty).
///
/// The snack is chosen by the action's own `requiredTier`, so it can never
/// contradict the tier badge the surface rendered beside the entry:
/// Pro/Enterprise gets the upsell, open-core gets the neutral "not
/// available yet".
///
/// The action → opener table is pinned against `LintcruxAction.values` by
/// the completeness test at the bottom: a new opener-backed action without
/// a row here fails by name.

/// Every action whose dispatch resolves an opener seam, paired with the
/// provider it resolves.
final Map<LintcruxAction, Provider<ProActionOpener?>>
_openerBackedActions = <LintcruxAction, Provider<ProActionOpener?>>{
  LintcruxAction.openWaiverReview: waiverReviewOpenerProvider,
  LintcruxAction.openBaselineComparison: baselineComparisonOpenerProvider,
  LintcruxAction.openBookmarksManager: bookmarkPanelOpenerProvider,
  LintcruxAction.manageFilterPresets: filterPresetManagerOpenerProvider,
  LintcruxAction.saveFilterPreset: saveFilterPresetOpenerProvider,
  LintcruxAction.setBaseline: setBaselineOpenerProvider,
  LintcruxAction.clearBaseline: clearBaselineOpenerProvider,
  LintcruxAction.toggleBookmarkForCurrentViolation:
      toggleBookmarkOpenerProvider,
  LintcruxAction.runVeribleDryRun: runVeribleDryRunOpenerProvider,
  LintcruxAction.applyVeribleFixes: applyVeribleFixesOpenerProvider,
  LintcruxAction.configureVeribleBinary: configureVeribleBinaryOpenerProvider,
  LintcruxAction.clearLintCache: clearLintCacheOpenerProvider,
  LintcruxAction.openLintCacheStats: openLintCacheStatsOpenerProvider,
  LintcruxAction.forceLintRunWithoutCache:
      forceLintRunWithoutCacheOpenerProvider,
  LintcruxAction.showRuleTrendChart: showRuleTrendChartOpenerProvider,
  LintcruxAction.showSeverityClassDriftChart:
      showSeverityClassDriftChartOpenerProvider,
  LintcruxAction.showProjectTrendChart: showProjectTrendChartOpenerProvider,
  LintcruxAction.showCalendarHeatmap: showCalendarHeatmapOpenerProvider,
  LintcruxAction.configureTrendRetention: configureTrendRetentionOpenerProvider,
  LintcruxAction.pinActiveProject: pinActiveProjectOpenerProvider,
  LintcruxAction.closeAllProjects: closeAllProjectsOpenerProvider,
  // The multi-project trio. These were once excluded from this table as
  // "deferrals with hand-coded snacks" — a description that stopped being true
  // when the Pro overlay shipped its switcher and cross-project search. They
  // dispatch through opener seams like every other Pro action, so they belong
  // here and get the same Pro-gated-snack contract.
  LintcruxAction.switchProject: switchProjectOpenerProvider,
  LintcruxAction.reopenRecentProject: reopenRecentProjectOpenerProvider,
  LintcruxAction.searchAcrossProjects: searchAcrossProjectsOpenerProvider,
};

void main() {
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PackageInfo.setMockInitialValues(
      appName: 'lintcrux',
      packageName: 'com.ferrite.lintcrux',
      version: '0.0.0',
      buildNumber: '0',
      buildSignature: '',
    );
    tempDir = await Directory.systemTemp.createTemp('lintcrux_seam_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Boots the real app with no Pro overrides — the open-core build.
  Future<void> bootOpenCore(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        // See the note in `test/widget_test.dart`: mounting `LintcruxApp`
        // outside `bootstrap()` still has to supply the beta-distribution
        // overrides.
        overrides: [
          ...telemetryDeclinedOverrides(),
          ...lintcruxPhase5Overrides(),
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
    final handler = manager.handlers[action];
    expect(handler, isNotNull);
    handler!();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
  }

  L10N l10nOf(WidgetTester tester) =>
      L10N.of(tester.element(find.byType(Navigator).first));

  group('open-core opener seams default to null', () {
    test('no opener-backed action resolves an implementation', () {
      final container = ProviderContainer(
        overrides: telemetryDeclinedOverrides(),
      );
      addTearDown(container.dispose);
      for (final entry in _openerBackedActions.entries) {
        expect(
          container.read(entry.value),
          isNull,
          reason:
              '${entry.key} resolves a non-null opener in open-core. A no-op '
              'default makes the dispatcher unable to detect the missing '
              'implementation, which is what turns the menu entry into a '
              'silent dead item.',
        );
      }
    });
  });

  group('open-core activation surfaces feedback, never silence', () {
    for (final entry in _openerBackedActions.entries) {
      final action = entry.key;
      testWidgets('${action.name} snacks instead of no-oping', (tester) async {
        await bootOpenCore(tester);
        dispatch(tester, action);
        await settle(tester);

        final l10n = l10nOf(tester);
        final label = action.label(l10n);
        final expected = action.requiredTier == LicenseTier.openCore
            ? l10n.snackFeatureNotAvailableYet(label)
            : l10n.snackFeatureRequiresPro(label);

        expect(
          find.text(expected),
          findsOneWidget,
          reason:
              '${action.name} produced no user-visible feedback in an '
              'open-core build.',
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the snack never contradicts the rendered tier badge', (
      tester,
    ) async {
      await bootOpenCore(tester);
      final l10n = l10nOf(tester);
      for (final action in _openerBackedActions.keys) {
        if (action.requiredTier != LicenseTier.openCore) continue;
        // An open-core-tier action renders no PRO badge, so telling the
        // user it "requires LintCrux Pro" would be a false upsell.
        expect(
          l10n.snackFeatureNotAvailableYet(action.label(l10n)),
          isNot(contains('Pro')),
          reason:
              '${action.name} declares the open-core tier but its feedback '
              'string implies a Pro upsell.',
        );
      }
    });
  });

  group('table completeness', () {
    test('every opener-backed action in the enum has a row', () {
      // Actions dispatched through an opener seam are exactly those whose
      // implementation lives in the Pro overlay. If a new one lands
      // without a row, its open-core feedback is untested.
      // Empty on purpose: every Pro-tier action dispatches through an
      // opener seam. It stays declared so a genuinely seam-less Pro
      // action has an obvious, documented place to be recorded rather
      // than being bolted onto the condition below.
      const knownNonOpenerProActions = <LintcruxAction>{};
      final missing = <LintcruxAction>[
        for (final a in LintcruxAction.values)
          if (a.requiredTier != LicenseTier.openCore &&
              !_openerBackedActions.containsKey(a) &&
              !knownNonOpenerProActions.contains(a))
            a,
      ];
      expect(
        missing,
        isEmpty,
        reason:
            'Pro/Enterprise-tier actions with no opener row and no hand-coded '
            'snack: ${missing.map((a) => a.name).join(', ')}. Each needs an '
            'entry in _openerBackedActions so its open-core feedback is '
            'pinned.',
      );
    });
  });
}
