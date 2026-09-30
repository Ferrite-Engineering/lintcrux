// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/core/shortcuts/action_category.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_context.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_descriptor.dart';

/// The single source of truth for where every [LintcruxAction] appears and
/// when it is enabled.
///
/// ## IMPORTANT — adding a new action
///
/// This is an **exhaustive `switch`**. Adding a value to [LintcruxAction]
/// fails to compile until a case lands here, which is the guardrail keeping
/// every new action wired into the single source of truth.
LintcruxActionDescriptor descriptorFor(LintcruxAction action) =>
    switch (action) {
      // ── Always available, workspace-independent ─────────────────────
      // Opening a project or workspace creates its own tab; the app-level
      // commands (settings, about, docs, updates, the issue reporter) and
      // the theme toggle never depend on workspace state.
      // On the toolbar as well: Open leads the canonical common block, and
      // Open Workspace / Import SARIF are LintCrux's own file chrome.
      LintcruxAction.openProject ||
      LintcruxAction.openWorkspace ||
      LintcruxAction.importSarif ||
      LintcruxAction.openSettings => const LintcruxActionDescriptor(
        surfaces: _everywhere,
      ),

      // ── Adding sources to an existing project ───────────────────────
      // On the toolbar, matching NetCrux, which surfaces the equivalent
      // `openSourceFiles`. Enablement is where the two products diverge,
      // and the divergence is real rather than an oversight: NetCrux's
      // flow OPENS the picked files into a new tab, so it is meaningful
      // on the empty canvas and is unconditionally enabled there.
      // LintCrux's appends them to the active tab's `.lintcrux` and
      // rewrites the file, so with no loaded project there is nothing to
      // append to — `_handleOpenSources` bails to the
      // `openSourcesNoActiveProject` snackbar. `_requiresProject` is
      // exactly that handler's own precondition (`hasProject` mirrors the
      // active tab's `currentProjectProvider`), so the button greys out
      // instead of offering an action that can only explain itself.
      LintcruxAction.openSources => const LintcruxActionDescriptor(
        surfaces: _everywhere,
        isEnabled: _requiresProject,
      ),

      LintcruxAction.importVivadoFilelist ||
      LintcruxAction.importEdam ||
      LintcruxAction.openSession ||
      LintcruxAction.newWorkspace ||
      LintcruxAction.newTab ||
      LintcruxAction.openAbout ||
      LintcruxAction.openDocumentation ||
      LintcruxAction.checkForUpdates ||
      LintcruxAction.submitIssue ||
      LintcruxAction.toggleTheme ||
      LintcruxAction.quit => const LintcruxActionDescriptor(
        surfaces: _menuPalette,
      ),

      // ── Command palette opener — menu only ──────────────────────────
      // Self-referential inside the palette, but it MUST stay reachable
      // from the menu, or unbinding its shortcut would make the palette
      // permanently inaccessible with no recovery path.
      LintcruxAction.openCommandPalette => const LintcruxActionDescriptor(
        surfaces: _menuOnly,
      ),

      // ── Cross-probe panel — always openable ─────────────────────────
      // The panel is the peer-discovery status surface, so it stays
      // openable at zero peers: hiding it would hide the only place that
      // explains why no peers are connected.
      LintcruxAction.openCrossProbePanel => const LintcruxActionDescriptor(
        surfaces: _everywhere,
      ),

      // ── Needs an open tab ───────────────────────────────────────────
      // These read or mutate per-tab state through the active tab's
      // container; with no tab they resolve the empty root scope.
      // The rest of the canonical common toolbar block: Save · Close ·
      // Find. All three need a tab to act on.
      LintcruxAction.saveSession ||
      LintcruxAction.closeActiveProject ||
      LintcruxAction.focusSearch => const LintcruxActionDescriptor(
        surfaces: _everywhere,
        isEnabled: _requiresTab,
      ),

      LintcruxAction.closeTab ||
      LintcruxAction.closeAllTabs ||
      LintcruxAction.closeAllProjects ||
      LintcruxAction.resetWorkspace ||
      LintcruxAction.saveWorkspaceAs ||
      LintcruxAction.pinActiveProject ||
      LintcruxAction.openTabDiagnostics => const LintcruxActionDescriptor(
        surfaces: _menuPalette,
        isEnabled: _requiresTab,
      ),

      // ── App-wide diagnostics — always available ─────────────────────
      LintcruxAction.openAppDiagnostics => const LintcruxActionDescriptor(
        surfaces: _menuPalette,
      ),

      // ── Multi-project management ────────────────────────────────────
      // Surface set and enablement mirror SimCrux's equivalent trio,
      // which is where LintCrux's implementation was mirrored from:
      // menu + palette, never the toolbar (the canonical common toolbar
      // block is Open / Import / Run / Cancel / Close / Search /
      // Settings in every suite product, and these are once-a-session
      // commands). Reopen Recent needs no open project — reopening one
      // is exactly what you do when you have none — while the switcher
      // and cross-project search both act over the loaded set.
      //
      // These three once carried NO surfaces at all. A "stub actions are
      // not surfaced" rule hid them as unshipped deferrals, which they had
      // been when that rule was written; the Pro overlay had in the
      // meantime shipped the whole feature set (its project UI overrides
      // wire the switcher dialog, the cross-project search service and
      // the tier gates). The result was a built, badged and
      // telemetry-instrumented Pro capability no user could reach. Do not
      // re-hide these without checking the overlay first.
      LintcruxAction.reopenRecentProject => const LintcruxActionDescriptor(
        surfaces: _menuPalette,
      ),
      LintcruxAction.switchProject ||
      LintcruxAction.searchAcrossProjects => const LintcruxActionDescriptor(
        surfaces: _menuPalette,
        isEnabled: _requiresProject,
      ),

      // ── Running the engines ─────────────────────────────────────────
      // A run needs a project, and starting a second run over a live one
      // is not something the engines support — so the run commands grey
      // out while one is in flight and Cancel greys out when none is.
      LintcruxAction.runAllEngines => const LintcruxActionDescriptor(
        surfaces: _everywhere,
        isEnabled: _canStartRun,
      ),
      // The toolbar's run control is one morphing Run/Cancel button, so the
      // cache-bypassing variant has no slot there — like every other Pro
      // lint-cache command it is a menu and palette entry.
      LintcruxAction.forceLintRunWithoutCache => const LintcruxActionDescriptor(
        surfaces: _menuPalette,
        isEnabled: _canStartRun,
      ),
      LintcruxAction.cancelRun => const LintcruxActionDescriptor(
        surfaces: _everywhere,
        isEnabled: _requiresRunInProgress,
      ),

      // ── Needs a loaded project ──────────────────────────────────────
      LintcruxAction.openWaiverReview ||
      LintcruxAction.openBaselineComparison ||
      LintcruxAction.showRuleTrendChart ||
      LintcruxAction.showSeverityClassDriftChart ||
      LintcruxAction.showProjectTrendChart ||
      LintcruxAction.showCalendarHeatmap ||
      LintcruxAction.configureTrendRetention ||
      LintcruxAction.openBookmarksManager ||
      LintcruxAction.runVeribleDryRun ||
      LintcruxAction.applyVeribleFixes ||
      LintcruxAction.clearLintCache ||
      LintcruxAction.openLintCacheStats ||
      LintcruxAction.saveFilterPreset ||
      LintcruxAction.manageFilterPresets ||
      LintcruxAction.clearBaseline => const LintcruxActionDescriptor(
        surfaces: _menuPalette,
        isEnabled: _requiresProject,
      ),

      // ── Configuring the Verible binary — project-independent ────────
      // It writes a setting, so it works before any project is open.
      LintcruxAction.configureVeribleBinary => const LintcruxActionDescriptor(
        surfaces: _menuPalette,
      ),

      // ── Needs violations to act on ──────────────────────────────────
      // Exporting an empty result set writes an empty file, and
      // baselining nothing records nothing.
      // The four export formats share one grouped (split) toolbar slot —
      // individually none would earn a button, together they earn one.
      LintcruxAction.exportSarif ||
      LintcruxAction.exportJson ||
      LintcruxAction.exportCsv ||
      LintcruxAction.exportHtml => const LintcruxActionDescriptor(
        surfaces: _everywhere,
        isEnabled: _requiresViolations,
      ),

      LintcruxAction.setBaseline => const LintcruxActionDescriptor(
        surfaces: _menuPalette,
        isEnabled: _requiresViolations,
      ),

      // ── Needs a selected violation ──────────────────────────────────
      LintcruxAction.toggleBookmarkForCurrentViolation =>
        const LintcruxActionDescriptor(
          surfaces: _menuPalette,
          isEnabled: _requiresSelectedViolation,
        ),

      // ── Pane management ─────────────────────────────────────────────
      LintcruxAction.splitPaneRight => const LintcruxActionDescriptor(
        surfaces: _menuPalette,
        isEnabled: _requiresTabSinglePane,
      ),
      LintcruxAction.closePane ||
      LintcruxAction.focusOtherPane => const LintcruxActionDescriptor(
        surfaces: _menuPalette,
        isEnabled: _requiresMultiPane,
      ),
      LintcruxAction.moveTabToOtherPane => const LintcruxActionDescriptor(
        surfaces: _menuPalette,
        isEnabled: _requiresTabMultiPane,
      ),

      // ── Tab navigation ──────────────────────────────────────────────
      LintcruxAction.nextTab ||
      LintcruxAction.previousTab => const LintcruxActionDescriptor(
        surfaces: _menuPalette,
        isEnabled: _requiresMultipleTabs,
      ),
    };

// ── derived selectors (the API every surface consumes) ───────────────────────

/// Whether [action] structurally appears in [surface] under [context].
bool isActionVisibleIn(
  LintcruxAction action,
  LintcruxActionSurface surface,
  LintcruxActionContext context,
) => descriptorFor(action).surfaces.contains(surface);

/// Whether [action] is currently enabled under [context].
bool isActionEnabled(LintcruxAction action, LintcruxActionContext context) =>
    descriptorFor(action).isEnabled(context);

/// Actions to render in [surface] under [context], grouped by
/// [ActionCategory]. Disabled actions are *included* — the menu greys them
/// out; only structurally-hidden actions are omitted.
Map<ActionCategory, List<LintcruxAction>> groupedActionsFor(
  LintcruxActionSurface surface,
  LintcruxActionContext context,
) {
  final result = <ActionCategory, List<LintcruxAction>>{
    for (final category in ActionCategory.values) category: <LintcruxAction>[],
  };
  for (final action in LintcruxAction.values) {
    if (isActionVisibleIn(action, surface, context)) {
      result[action.category]!.add(action);
    }
  }
  return result;
}

/// Actions to list in the command palette — visible **and** enabled. The
/// palette has no greyed state, so a disabled action is omitted rather than
/// shown inert.
List<LintcruxAction> paletteActionsFor(LintcruxActionContext context) =>
    LintcruxAction.values
        .where(
          (a) =>
              isActionVisibleIn(a, LintcruxActionSurface.palette, context) &&
              isActionEnabled(a, context),
        )
        .toList();

// ── surface sets ─────────────────────────────────────────────────────────────

const Set<LintcruxActionSurface> _everywhere = {
  LintcruxActionSurface.toolbar,
  LintcruxActionSurface.menu,
  LintcruxActionSurface.palette,
};

const Set<LintcruxActionSurface> _menuPalette = {
  LintcruxActionSurface.menu,
  LintcruxActionSurface.palette,
};

const Set<LintcruxActionSurface> _menuOnly = {LintcruxActionSurface.menu};

// ── enablement predicates (top-level for const tear-off) ─────────────────────

bool _requiresTab(LintcruxActionContext c) => c.hasOpenTab;
bool _requiresProject(LintcruxActionContext c) => c.hasProject;
bool _requiresViolations(LintcruxActionContext c) => c.hasViolations;
bool _requiresSelectedViolation(LintcruxActionContext c) =>
    c.hasSelectedViolation;
bool _requiresRunInProgress(LintcruxActionContext c) => c.runInProgress;
bool _canStartRun(LintcruxActionContext c) => c.hasProject && !c.runInProgress;
bool _requiresMultiPane(LintcruxActionContext c) => c.paneCount >= 2;
bool _requiresTabSinglePane(LintcruxActionContext c) =>
    c.hasOpenTab && c.paneCount == 1;
bool _requiresTabMultiPane(LintcruxActionContext c) =>
    c.hasOpenTab && c.paneCount >= 2;
bool _requiresMultipleTabs(LintcruxActionContext c) =>
    c.tabCountInActivePane > 1;
