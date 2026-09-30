// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// Localized display name for each [LintcruxAction].
///
/// Lives outside the enum because the cross-suite `CruxAction` interface
/// deliberately does not include localized labels — labels reference each
/// product's own `L10N` class. Mirrors WaveCrux's
/// `ShortcutActionLabel` extension under `lib/core/shortcuts/`.
extension LintcruxActionLabel on LintcruxAction {
  /// Returns the localized human-readable name for this action, suitable
  /// for menus, the command palette, settings, and the overflow action
  /// menu.
  String label(L10N l10n) => switch (this) {
    LintcruxAction.openProject => l10n.actionOpenProject,
    LintcruxAction.openSources => l10n.actionOpenSources,
    LintcruxAction.importVivadoFilelist => l10n.actionImportVivadoFilelist,
    LintcruxAction.importEdam => l10n.actionImportEdam,
    LintcruxAction.quit => l10n.actionQuit,
    LintcruxAction.runAllEngines => l10n.actionRunAllEngines,
    LintcruxAction.cancelRun => l10n.actionCancelRun,
    LintcruxAction.toggleTheme => l10n.actionToggleTheme,
    LintcruxAction.openCommandPalette => l10n.actionOpenCommandPalette,
    LintcruxAction.focusSearch => l10n.actionFocusSearch,
    LintcruxAction.openSettings => l10n.actionOpenSettings,
    LintcruxAction.resetWorkspace => l10n.actionResetWorkspace,
    LintcruxAction.saveSession => l10n.actionSaveSession,
    LintcruxAction.openSession => l10n.actionOpenSession,
    LintcruxAction.importSarif => l10n.actionImportSarif,
    LintcruxAction.exportSarif => l10n.actionExportSarif,
    LintcruxAction.exportJson => l10n.actionExportJson,
    LintcruxAction.exportCsv => l10n.actionExportCsv,
    LintcruxAction.exportHtml => l10n.actionExportHtml,
    LintcruxAction.openTabDiagnostics => l10n.actionOpenTabDiagnostics,
    LintcruxAction.openAppDiagnostics => l10n.actionOpenAppDiagnostics,
    LintcruxAction.saveFilterPreset => l10n.actionSaveFilterPreset,
    LintcruxAction.manageFilterPresets => l10n.actionManageFilterPresets,
    LintcruxAction.openAbout => l10n.actionOpenAbout,
    // Update mechanism + beta issue reporter (open-core tier).
    LintcruxAction.checkForUpdates => l10n.actionCheckForUpdates,
    LintcruxAction.submitIssue => l10n.actionSubmitIssue,
    LintcruxAction.openDocumentation => l10n.actionOpenDocumentation,
    // Workspace / pane / tab actions.
    LintcruxAction.newWorkspace => l10n.actionNewWorkspace,
    LintcruxAction.saveWorkspaceAs => l10n.actionSaveWorkspaceAs,
    LintcruxAction.openWorkspace => l10n.actionOpenWorkspace,
    LintcruxAction.splitPaneRight => l10n.actionSplitPaneRight,
    LintcruxAction.closePane => l10n.actionClosePane,
    LintcruxAction.focusOtherPane => l10n.actionFocusOtherPane,
    LintcruxAction.moveTabToOtherPane => l10n.actionMoveTabToOtherPane,
    LintcruxAction.newTab => l10n.actionNewTab,
    LintcruxAction.closeTab => l10n.actionCloseTab,
    LintcruxAction.nextTab => l10n.actionNextTab,
    LintcruxAction.previousTab => l10n.actionPreviousTab,
    // Cross-probe panel.
    LintcruxAction.openCrossProbePanel => l10n.actionOpenCrossProbePanel,
    // Managed-waiver review screen (Pro tier).
    LintcruxAction.openWaiverReview => l10n.actionOpenWaiverReview,
    // Baseline & delta actions (Pro tier).
    LintcruxAction.setBaseline => l10n.actionSetBaseline,
    LintcruxAction.clearBaseline => l10n.actionClearBaseline,
    LintcruxAction.openBaselineComparison => l10n.actionOpenBaselineComparison,
    // Trend tracking actions (Pro tier).
    LintcruxAction.showRuleTrendChart => l10n.actionShowRuleTrendChart,
    LintcruxAction.showSeverityClassDriftChart =>
      l10n.actionShowSeverityClassDriftChart,
    LintcruxAction.showProjectTrendChart => l10n.actionShowProjectTrendChart,
    LintcruxAction.showCalendarHeatmap => l10n.actionShowCalendarHeatmap,
    LintcruxAction.configureTrendRetention =>
      l10n.actionConfigureTrendRetention,
    // Filter presets & violation bookmarks (Pro tier).
    LintcruxAction.openBookmarksManager => l10n.actionOpenBookmarksManager,
    LintcruxAction.toggleBookmarkForCurrentViolation =>
      l10n.actionToggleBookmarkForCurrentViolation,
    // Verible auto-fix integration (Pro tier).
    LintcruxAction.runVeribleDryRun => l10n.actionRunVeribleDryRun,
    LintcruxAction.applyVeribleFixes => l10n.actionApplyVeribleFixes,
    LintcruxAction.configureVeribleBinary => l10n.actionConfigureVeribleBinary,
    // Lint run caching (Pro tier).
    LintcruxAction.clearLintCache => l10n.actionClearLintCache,
    LintcruxAction.openLintCacheStats => l10n.actionOpenLintCacheStats,
    LintcruxAction.forceLintRunWithoutCache =>
      l10n.actionForceLintRunWithoutCache,
    // Multi-project workspace.
    LintcruxAction.closeActiveProject => l10n.actionCloseActiveProject,
    LintcruxAction.switchProject => l10n.actionSwitchProject,
    LintcruxAction.reopenRecentProject => l10n.actionReopenRecentProject,
    LintcruxAction.pinActiveProject => l10n.actionPinActiveProject,
    LintcruxAction.closeAllProjects => l10n.actionCloseAllProjects,
    LintcruxAction.closeAllTabs => l10n.actionCloseAllTabs,
    LintcruxAction.searchAcrossProjects => l10n.actionSearchAcrossProjects,
  };
}
