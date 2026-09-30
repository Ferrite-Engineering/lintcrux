// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_menu_bar/crux_menu_bar.dart';
import 'package:lintcrux/core/shortcuts/action_category.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';

/// Declarative ordering and grouping of LintCrux's menu-bar actions, in the
/// suite-wide canonical group order (see the shared `crux_menu_bar` README).
///
/// This table is the single source of truth for the *order* menu items appear
/// in and *where the separators fall*. Before it, LintCrux rendered every
/// category as one undifferentiated run in enum-declaration order: the File
/// menu was 19 consecutive rows with New Workspace seventh and Reset Workspace
/// fourth, opens and saves interleaved.
///
/// ## Canonical group order
///
/// - **File** — New | Open/Import | Projects | Save | Export | Close | Reset
/// - **View** — Command Palette | Panels | Filters | Panes | Tabs | Appearance
/// - **Search** — Find | Find across projects
/// - **Tools** — Run | Waivers | Baseline | Trends | Bookmarks | Verible |
///   Cache | Diagnostics (last)
/// - **Help** — Documentation | Report Issue | Check for Updates | About
///
/// ## Not in this table on purpose
///
/// `openSettings` and `quit` are placed by `CruxDesktopMenuBar` from
/// [kAppMenuActions] because their placement is platform-specific. `openAbout`
/// and `checkForUpdates` *are* here, under Help — their Windows/Linux home —
/// and the macOS renderer hoists them into the application menu.
///
/// `ActionCategory.navigate` and `ActionCategory.edit` have no entries:
/// LintCrux has no navigation or editing actions, so neither menu renders.
/// Before this pass the Navigate menu was silently omitted for the same
/// reason, leaving LintCrux with one fewer top-level menu than its peers —
/// now that is explicit rather than incidental.
const CruxMenuLayout<LintcruxAction> kMenuLayout = {
  // ── File ──────────────────────────────────────────────────────────────────
  ActionCategory.file: [
    [
      LintcruxAction.newWorkspace,
      LintcruxAction.newTab,
    ],
    [
      LintcruxAction.openProject,
      LintcruxAction.openSources,
      LintcruxAction.openWorkspace,
      LintcruxAction.openSession,
      LintcruxAction.importVivadoFilelist,
      LintcruxAction.importEdam,
      LintcruxAction.importSarif,
    ],
    // The projects group, in SimCrux's order — switch, reopen, pin.
    // SimCrux is where LintCrux's multi-project implementation was
    // mirrored from, and its File menu groups the same three together
    // between the open/import block and the close block.
    [
      LintcruxAction.switchProject,
      LintcruxAction.reopenRecentProject,
      LintcruxAction.pinActiveProject,
    ],
    [
      LintcruxAction.saveSession,
      LintcruxAction.saveWorkspaceAs,
    ],
    // Exports live here rather than under Tools —
    // they write a file, and WaveCrux and NetCrux already grouped theirs
    // with the other File output commands.
    [
      LintcruxAction.exportSarif,
      LintcruxAction.exportJson,
      LintcruxAction.exportCsv,
      LintcruxAction.exportHtml,
    ],
    [
      LintcruxAction.closeTab,
      LintcruxAction.closeAllTabs,
      LintcruxAction.closeActiveProject,
      LintcruxAction.closeAllProjects,
    ],
    [
      LintcruxAction.resetWorkspace,
    ],
  ],

  // ── View ──────────────────────────────────────────────────────────────────
  ActionCategory.view: [
    [
      LintcruxAction.openCommandPalette,
    ],
    [
      LintcruxAction.openCrossProbePanel,
    ],
    [
      LintcruxAction.saveFilterPreset,
      LintcruxAction.manageFilterPresets,
    ],
    [
      LintcruxAction.splitPaneRight,
      LintcruxAction.closePane,
      LintcruxAction.focusOtherPane,
      LintcruxAction.moveTabToOtherPane,
    ],
    [
      LintcruxAction.nextTab,
      LintcruxAction.previousTab,
    ],
    [
      LintcruxAction.toggleTheme,
    ],
  ],

  // ── Search ────────────────────────────────────────────────────────────────
  // Find, then Find across projects in its own group — SimCrux's shape,
  // and what this file's "Canonical group order" already documented.
  ActionCategory.search: [
    [
      LintcruxAction.focusSearch,
    ],
    [
      LintcruxAction.searchAcrossProjects,
    ],
  ],

  // ── Tools ─────────────────────────────────────────────────────────────────
  ActionCategory.tools: [
    [
      LintcruxAction.runAllEngines,
      LintcruxAction.forceLintRunWithoutCache,
      LintcruxAction.cancelRun,
    ],
    [
      LintcruxAction.openWaiverReview,
    ],
    [
      LintcruxAction.setBaseline,
      LintcruxAction.clearBaseline,
      LintcruxAction.openBaselineComparison,
    ],
    [
      LintcruxAction.showRuleTrendChart,
      LintcruxAction.showSeverityClassDriftChart,
      LintcruxAction.showProjectTrendChart,
      LintcruxAction.showCalendarHeatmap,
      LintcruxAction.configureTrendRetention,
    ],
    [
      LintcruxAction.openBookmarksManager,
      LintcruxAction.toggleBookmarkForCurrentViolation,
    ],
    [
      LintcruxAction.runVeribleDryRun,
      LintcruxAction.applyVeribleFixes,
      LintcruxAction.configureVeribleBinary,
    ],
    [
      LintcruxAction.clearLintCache,
      LintcruxAction.openLintCacheStats,
    ],
    [
      LintcruxAction.openTabDiagnostics,
      LintcruxAction.openAppDiagnostics,
    ],
  ],

  // ── Help ──────────────────────────────────────────────────────────────────
  // About and Check for Updates are hoisted into the macOS application menu.
  ActionCategory.help: [
    [
      LintcruxAction.openDocumentation,
    ],
    [
      LintcruxAction.submitIssue,
    ],
    [
      LintcruxAction.checkForUpdates,
    ],
    [
      LintcruxAction.openAbout,
    ],
  ],
};

/// The four actions whose menu placement the host platform decides.
const CruxAppMenuActions<LintcruxAction> kAppMenuActions = CruxAppMenuActions(
  about: LintcruxAction.openAbout,
  checkForUpdates: LintcruxAction.checkForUpdates,
  settings: LintcruxAction.openSettings,
  quit: LintcruxAction.quit,
);
