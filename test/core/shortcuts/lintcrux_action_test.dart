// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';

void main() {
  group('LintcruxAction', () {
    test('every value is a CruxAction with the lintcrux. namespace', () {
      for (final a in LintcruxAction.values) {
        expect(a, isA<CruxAction>());
        expect(a.id, startsWith('lintcrux.'));
        expect(a.id, 'lintcrux.${a.name}');
      }
    });

    test('id values are unique across the enum', () {
      final seen = <String>{};
      for (final a in LintcruxAction.values) {
        expect(seen.add(a.id), isTrue, reason: 'duplicate id ${a.id}');
      }
    });

    test('category mapping is total — every value resolves to a category', () {
      for (final a in LintcruxAction.values) {
        // The switch is exhaustive at compile time; this exercise also
        // protects against accidental future changes that drop a case.
        expect(a.category, isA<ActionCategory>());
      }
    });

    test('the Pro action set is exactly the documented one — a mis-declared '
        'tier fails here even though the switch still compiles', () {
      // The compile-time guard (an exhaustive switch with no `default`)
      // catches an action that declares NO tier. It cannot catch one that
      // declares the WRONG tier, which is the form the defect actually
      // takes: a Pro feature shipping without its badge, or an open-core
      // action badged PRO and telling the user to buy something they
      // already have. This second source of truth closes that gap.
      // Mirrors the SimCrux / NetCrux set-equality guard.
      const proActions = <LintcruxAction>{
        LintcruxAction.openWaiverReview,
        LintcruxAction.setBaseline,
        LintcruxAction.clearBaseline,
        LintcruxAction.openBaselineComparison,
        LintcruxAction.showRuleTrendChart,
        LintcruxAction.showSeverityClassDriftChart,
        LintcruxAction.showProjectTrendChart,
        LintcruxAction.showCalendarHeatmap,
        LintcruxAction.configureTrendRetention,
        LintcruxAction.runVeribleDryRun,
        LintcruxAction.applyVeribleFixes,
        LintcruxAction.configureVeribleBinary,
        LintcruxAction.clearLintCache,
        LintcruxAction.openLintCacheStats,
        LintcruxAction.forceLintRunWithoutCache,
        LintcruxAction.openBookmarksManager,
        LintcruxAction.toggleBookmarkForCurrentViolation,
        LintcruxAction.pinActiveProject,
        LintcruxAction.closeAllProjects,
        LintcruxAction.searchAcrossProjects,
        LintcruxAction.switchProject,
        LintcruxAction.reopenRecentProject,
      };

      expect(
        LintcruxAction.values
            .where((a) => a.requiredTier == LicenseTier.pro)
            .toSet(),
        proActions,
        reason:
            'The Pro-tier roster drifted. Either an action gained/lost its '
            'tier without updating this set, or a new action was added with '
            'the wrong tier.',
      );
      expect(
        LintcruxAction.openBookmarksManager.requiredTier,
        LicenseTier.pro,
      );
      expect(
        LintcruxAction.toggleBookmarkForCurrentViolation.requiredTier,
        LicenseTier.pro,
      );
    });

    test('multi-project workspace pinning / close-all / cross-project search '
        'are Pro tier', () {
      // Open / close / switch / reopen-recent remain
      // open-core so the multi-project surface is discoverable under
      // [NoopProjectRegistry]; only the genuinely Pro-only operations
      // are gated.
      expect(
        LintcruxAction.pinActiveProject.requiredTier,
        LicenseTier.pro,
      );
      expect(
        LintcruxAction.closeAllProjects.requiredTier,
        LicenseTier.pro,
      );
      expect(
        LintcruxAction.searchAcrossProjects.requiredTier,
        LicenseTier.pro,
      );
    });

    test('multi-project open / close-active are open-core; switch and '
        'reopen-recent are Pro', () {
      // openProject / closeActiveProject work standalone under
      // NoopProjectRegistry, so they stay free. Switching between open
      // projects and reopening a recent are defined by the persistent
      // registry, which only the Pro overlay installs — the registry is a
      // Pro feature in every product that has one.
      expect(LintcruxAction.openProject.requiredTier, LicenseTier.openCore);
      expect(
        LintcruxAction.closeActiveProject.requiredTier,
        LicenseTier.openCore,
      );
      expect(LintcruxAction.switchProject.requiredTier, LicenseTier.pro);
      expect(LintcruxAction.reopenRecentProject.requiredTier, LicenseTier.pro);
    });

    test('all other current actions default to openCore', () {
      const proActions = {
        LintcruxAction.openWaiverReview,
        LintcruxAction.setBaseline,
        LintcruxAction.clearBaseline,
        LintcruxAction.openBaselineComparison,
        LintcruxAction.showRuleTrendChart,
        LintcruxAction.showSeverityClassDriftChart,
        LintcruxAction.showProjectTrendChart,
        LintcruxAction.showCalendarHeatmap,
        LintcruxAction.configureTrendRetention,
        LintcruxAction.openBookmarksManager,
        LintcruxAction.toggleBookmarkForCurrentViolation,
        LintcruxAction.runVeribleDryRun,
        LintcruxAction.applyVeribleFixes,
        LintcruxAction.configureVeribleBinary,
        LintcruxAction.clearLintCache,
        LintcruxAction.openLintCacheStats,
        LintcruxAction.forceLintRunWithoutCache,
        // Multi-project workspace Pro-tier actions —
        // every action whose meaning is defined by the persistent
        // project registry.
        LintcruxAction.pinActiveProject,
        LintcruxAction.closeAllProjects,
        LintcruxAction.searchAcrossProjects,
        LintcruxAction.switchProject,
        LintcruxAction.reopenRecentProject,
      };
      for (final action in LintcruxAction.values) {
        if (proActions.contains(action)) continue;
        expect(
          action.requiredTier,
          LicenseTier.openCore,
          reason:
              '${action.name} should default to openCore until '
              'explicitly mapped to a higher tier',
        );
      }
    });
  });

  group('ShortcutActionIntent', () {
    test('wraps the originating LintcruxAction verbatim', () {
      const intent = ShortcutActionIntent(LintcruxAction.openCommandPalette);
      expect(intent.action, LintcruxAction.openCommandPalette);
    });
  });
}
