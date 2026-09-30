// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:flutter/widgets.dart';

/// All keyboard-triggered actions recognized by LintCrux's shortcut system.
///
/// Implements the cross-suite [CruxAction] interface so generic
/// infrastructure (command palette, menu builders, telemetry sinks) can
/// reason about LintCrux actions alongside actions from the other Crux
/// products (WaveCrux, NetCrux, SimCrux) without depending on this
/// specific enum. Each value's `id` is namespaced with the
/// `lintcrux.` prefix to avoid cross-product collisions.
///
/// Covers the File / View / Run / Filter / Waivers / Tools / Help
/// surfaces. The infrastructure is the binding contract; the action set
/// grows as features land.
enum LintcruxAction implements CruxAction {
  // ── App / file ───────────────────────────────────────────────────────
  /// Open a `.lintcrux` project file via the standard file picker.
  ///
  /// Default binding: Cmd/Ctrl+O.
  openProject,

  /// Open one or more raw source files (Verilog / SystemVerilog / VHDL).
  ///
  /// Default binding: Cmd/Ctrl+Shift+O.
  openSources,

  /// Import a Vivado-style `.f` filelist into a new
  /// `.lintcrux` project. No default keyboard shortcut; reachable via
  /// the platform File menu (`File → Import → Vivado Filelist…`) and
  /// the command palette.
  importVivadoFilelist,

  /// Import a FuseSoC/Edalize EDAM (`.eda.yml`) file into a new
  /// `.lintcrux` project. No default keyboard shortcut; reachable via
  /// the platform File menu (`File → Import FuseSoC EDAM…`) and the
  /// command palette. The headless twin is `--import-edam`.
  importEdam,

  /// Open the settings screen.
  ///
  /// Default binding: Cmd/Ctrl+,.
  ///
  /// Declared BEFORE [quit] deliberately: the macOS application menu
  /// renders App-category actions in enum-declaration order, and the
  /// platform convention is About · Settings… · Quit.
  openSettings,

  /// Quit the LintCrux app.
  ///
  /// Default binding: Cmd/Ctrl+Q.
  quit,

  // ── Run ──────────────────────────────────────────────────────────────
  /// Run every enabled engine against the active project.
  ///
  /// Default binding: F5.
  runAllEngines,

  /// Cancel an in-progress run.
  ///
  /// Default binding: Esc (suite-wide cancel/stop convention).
  cancelRun,

  // ── View ─────────────────────────────────────────────────────────────
  /// Toggle the light / dark theme.
  ///
  /// Default binding: Cmd/Ctrl+Shift+K (Cmd/Ctrl+T belongs to [newTab]).
  toggleTheme,

  // ── Search / palette ─────────────────────────────────────────────────
  /// Open the VS Code-style command palette.
  ///
  /// Default binding: Cmd/Ctrl+Shift+P.
  openCommandPalette,

  /// Open the Find-in-Violations search dialog over the active tab's
  /// violation store (substring / glob / regex over rule id + message;
  /// picking a result selects the violation). The inline rule-id filter
  /// chip in the violations panel stays available for quick filtering;
  /// this is the richer modal find surface.
  ///
  /// Default binding: Cmd/Ctrl+F.
  focusSearch,

  // ── Workspace / settings ─────────────────────────────────────────────
  /// Empty the current workspace after a single confirmation dialog.
  /// Mirrors WaveCrux's `resetWorkspace`.
  resetWorkspace,

  // ── Session ──────────────────────────────────────────────────────────
  /// Save the active project + table state as a `.lintcrux-session`
  /// file. No default keyboard shortcut.
  saveSession,

  /// Open a `.lintcrux-session` file. No default keyboard shortcut.
  openSession,

  /// Import a CI-generated SARIF report (`.sarif` / `.json`) into a
  /// read-only imported-report viewer, without re-running any engine.
  /// The desktop counterpart of the web read-only mode's "Open SARIF
  /// File…" flow. No default keyboard shortcut; reachable via the File
  /// menu, the command palette, the toolbar, and the welcome screen.
  importSarif,

  // ── Tools (export / diagnostics) ─────────────────────────────────────
  /// Export the current violation set as SARIF 2.1.0. No default
  /// keyboard shortcut.
  exportSarif,

  /// Export the current violation set as JSON. No default keyboard
  /// shortcut.
  exportJson,

  /// Export the current violation set as CSV. No default keyboard
  /// shortcut.
  exportCsv,

  /// Export the current violation set as a single-page HTML dashboard.
  /// No default keyboard shortcut.
  exportHtml,

  /// Open the Tab Diagnostics drawer for the active project. No default
  /// keyboard shortcut.
  openTabDiagnostics,

  /// Open the App Diagnostics dialog. No default keyboard shortcut.
  openAppDiagnostics,

  // ── Filter presets ───────────────────────────────────────────────────
  /// Save the current violation-table filter state as a named preset.
  /// No default keyboard shortcut.
  saveFilterPreset,

  /// Open the manage-filter-presets dialog. No default keyboard
  /// shortcut.
  manageFilterPresets,

  // ── Workspace / pane / tab ───────────────────────────────
  /// Close the current workspace and start a fresh empty
  /// one. No default keyboard shortcut; reachable via the platform
  /// menu bar and the command palette.
  newWorkspace,

  /// Save the current workspace under a user-chosen
  /// filename. No default keyboard shortcut.
  saveWorkspaceAs,

  /// Load a `.lintcrux-workspace` file, replacing the
  /// current workspace. No default keyboard shortcut.
  openWorkspace,

  /// Split the active pane horizontally. Default
  /// binding: Cmd/Ctrl+\.
  splitPaneRight,

  /// Close the active pane (merging its tabs into the
  /// surviving pane). Default binding: Cmd/Ctrl+K W (chord).
  closePane,

  /// Toggle focus to the non-active pane. Default
  /// binding: Cmd/Ctrl+K → (chord).
  focusOtherPane,

  /// Move the active tab to the other pane. No default
  /// keyboard shortcut (command palette only).
  moveTabToOtherPane,

  /// Create a new empty tab in the active pane. Default
  /// binding: Cmd/Ctrl+T.
  newTab,

  /// Close the active tab. Default binding: Cmd/Ctrl+W.
  closeTab,

  /// Activate the next tab in the active pane. Default
  /// binding: Ctrl+Tab.
  nextTab,

  /// Activate the previous tab in the active pane.
  /// Default binding: Ctrl+Shift+Tab.
  previousTab,

  // ── Help ─────────────────────────────────────────────────────────────
  /// Show the About LintCrux dialog. No default keyboard shortcut —
  /// reachable via the platform menu bar and the command palette only.
  openAbout,

  /// Run a manual update check against the LintCrux version
  /// manifest. Always runs, regardless of the Settings → General
  /// "Automatically check for updates" toggle. Open-core tier — no badge.
  /// No default keyboard shortcut; reachable via the platform menu bar, the
  /// command palette, and the About dialog.
  checkForUpdates,

  /// Open the beta issue reporter, which collects a
  /// privacy-scrubbed diagnostic snapshot and opens a pre-filled GitHub
  /// new-issue page. Open to every tier — no badge, no feature gate. No
  /// default keyboard shortcut; reachable via the platform menu bar, the
  /// command palette, and the About dialog.
  submitIssue,

  /// Open the online LintCrux documentation (docs.lintcrux.app) in the
  /// user's browser. Open Core and never tier-gated — every suite Help
  /// menu leads with it.
  openDocumentation,

  // ── Remote / cross-probe ───────────────────────────────────
  /// Open the cross-probe panel showing connected CXP peers,
  /// the recent cross-probe event log, and the CXP server status.
  ///
  /// Default binding: Cmd/Ctrl+Shift+X (the suite-wide cross-probe key);
  /// also reachable via the platform menu bar and the command palette.
  openCrossProbePanel,

  // ── Waivers (Pro tier) ─────────────────────────────────────
  /// Open the managed-waiver review screen for the active
  /// project (the table of every waiver with edit / delete row
  /// actions plus expiration tracking). Pro-tier feature; the
  /// command-palette entry / menu item carry
  /// `LintCruxFeatureTierBadge(LicenseTier.pro)` and activation is gated by
  /// `FeatureGate.isAvailable`. Open-core dispatch reads
  /// `waiverReviewOpenerProvider`, which the Pro overlay overrides to
  /// mount the actual screen.
  openWaiverReview,

  // ── Baseline & delta (Pro tier) ────────────────────────────
  /// Snapshot the current run's active violations as the
  /// project's baseline. Subsequent runs surface only the delta (new
  /// violations introduced after the baseline). Pro-tier; the command-
  /// palette entry / menu item carry `LintCruxFeatureTierBadge(LicenseTier.pro)`
  /// and activation is gated by `FeatureGate.isAvailable`. The actual
  /// dispatch happens through `BaselineStore.setBaseline` which is
  /// no-op in open-core and JSON-file-backed in the Pro overlay.
  setBaseline,

  /// Clear the project's active baseline. After this, every
  /// violation is reported (the delta view becomes equivalent to the
  /// full violations list). Pro-tier; same badge + gate conventions
  /// as `setBaseline`.
  clearBaseline,

  /// Open the baseline-vs-current comparison screen
  /// (sections: New / Persisting / Resolved, each filterable, each
  /// with a copy-as-JSON / export action). Pro-tier; same badge + gate
  /// conventions. Dispatched through a Pro-overlay opener provider in
  /// the same shape as `waiverReviewOpenerProvider`.
  openBaselineComparison,

  // ── Trend tracking (Pro tier) ──────────────────────────────
  /// Open the per-rule trend chart screen for the rule
  /// selected in the violations panel (or a manually picked rule).
  /// Pro-tier; renders the tier badge and gates activation via
  /// `FeatureGate.isAvailable`. The actual screen is mounted by the
  /// Pro overlay.
  showRuleTrendChart,

  /// Open the severity-class drift chart screen (stacked
  /// area chart of error / warning / note counts over time).
  /// Pro-tier; same badge + gate conventions.
  showSeverityClassDriftChart,

  /// Open the project trend chart screen (total
  /// violations per run over time). Pro-tier; same badge + gate
  /// conventions.
  showProjectTrendChart,

  /// Open the calendar heatmap screen (GitHub-style
  /// contributions grid of per-day violation activity over a
  /// 30 / 90 / 365-day window). Pro-tier; same badge + gate
  /// conventions. The actual screen is mounted by the Pro overlay
  /// through `showCalendarHeatmapOpenerProvider`.
  showCalendarHeatmap,

  /// Open the trend retention configuration UI (Settings
  /// → Trends section). Pro-tier; same badge + gate conventions.
  configureTrendRetention,

  // ── Filter presets & violation bookmarks (Pro tier) ───────

  /// Open the bookmark management panel (the dockable list of
  /// every bookmarked violation grouped by file path, with stale-bookmark
  /// filter chips). Pro-tier; renders the tier badge and gates
  /// activation via `FeatureGate.isAvailable`. The panel is mounted by
  /// the Pro overlay through `bookmarkPanelOpenerProvider`.
  openBookmarksManager,

  /// Toggle a bookmark for the currently-selected violation
  /// (or the row under the cursor when invoked from a row context
  /// menu). Pro-tier; renders the tier badge and gates activation via
  /// `FeatureGate.isAvailable`. Dispatches through
  /// `toggleBookmarkOpenerProvider`, which is null in the open core, so the
  /// action answers with the "requires LintCrux Pro" notice there.
  toggleBookmarkForCurrentViolation,

  // ─── Verible auto-fix integration (Pro tier) ───────
  /// Runs Verible's auto-fix engine in dry-run mode
  /// against the active project. Opens the `FixReviewDialog` on
  /// completion so the user can audit + apply a subset of the
  /// proposed fixes. Pro-tier; renders the tier badge and gates
  /// activation via `FeatureGate.isAvailable`. Disabled when the
  /// installed Verible binary is missing or too old; the disabled
  /// tooltip surfaces the install / upgrade hint.
  runVeribleDryRun,

  /// Applies the currently-selected proposals from
  /// the open `FixReviewDialog`. Context-aware: only meaningful when
  /// a review dialog is mounted. Surfaced primarily by the dialog's
  /// own Apply button; the registry entry exists so the command
  /// palette / menu bar can dispatch the apply when the dialog is
  /// open. Pro-tier.
  applyVeribleFixes,

  /// Opens the Settings → External Tools → Verible section so the user can
  /// configure the binary path and per-feature toggles. Pro-tier.
  configureVeribleBinary,

  // ─── Lint run caching (Pro tier) ───────────────────
  /// Wipes every cached lint result for the active project after a single
  /// confirmation. Pro-tier; gated by `FeatureGate.isAvailable` with the tier
  /// badge always visible. The actual store wipe goes through
  /// [LintRunCacheService.clearAll].
  clearLintCache,

  /// Opens the Settings → Lint Cache section
  /// scrolled to the live-stats panel so users can audit hit rate
  /// + entry count + estimated time saved at any moment. Pro-tier.
  openLintCacheStats,

  /// Runs lint once with the cache bypassed in
  /// both directions (no lookups, no stores) for that single
  /// invocation, regardless of the cache-enabled toggle. Pro-tier;
  /// useful when the user suspects a stale entry is masking an
  /// engine update.
  forceLintRunWithoutCache,

  // ─── Multi-project workspace ────────────────────────
  /// Close the currently-active project tab in the
  /// multi-project workspace. Open-core action (single-project mode
  /// supports this as the inverse of `openProject`); under the Pro
  /// overlay, the closed project moves to the recent-projects list
  /// and the next-most-recent tab becomes active.
  closeActiveProject,

  /// Open the project switcher dialog. Cmd/Ctrl+P,
  /// matching SimCrux; menu / palette, never the toolbar.
  /// Pro-tier action (the multi-project registry is Pro; see
  /// [LintcruxActionRequiredTier.requiredTier]); renders even under [NoopProjectRegistry]
  /// so users discover the surface and see the recently-closed list once
  /// they upgrade. Under the Pro overlay, the dialog ranks open and
  /// recent projects by MRU + fuzzy match.
  switchProject,

  /// Reopen the most-recently-closed project from
  /// the recent-projects list. Pro-tier action (see
  /// [LintcruxActionRequiredTier.requiredTier]); no-op under [NoopProjectRegistry] (no
  /// recents are retained). Pro overlay re-hydrates the project including
  /// per-project state.
  reopenRecentProject,

  /// Pro-tier action that pins (or unpins) the
  /// active project tab. Pinned tabs survive [closeAllProjects].
  /// Open-core no-op (single-project mode); the command-palette /
  /// menu entry still renders so users see the feature exists.
  pinActiveProject,

  /// Pro-tier action that closes every open project except pinned ones.
  /// Open-core no-op; under the Pro overlay, the workspace falls back to the
  /// most-recently-active surviving project (or empty when none remain).
  closeAllProjects,

  /// Close every open workspace tab, after confirmation.
  ///
  /// Open-core, unconditional: this is the plain tab-closing
  /// capability — no project registry, no pinning, no recents. It is
  /// what [closeAllProjects] actually did in an open-core build, given
  /// its own honest name so free users keep the capability while the
  /// registry-aware, pin-respecting variant carries the PRO badge.
  ///
  /// Distinct from [resetWorkspace]: that action replaces the whole
  /// document with `Workspace.empty()`, discarding the `extras` map
  /// (panel visibility and other ambient layout flags) along with the
  /// tabs. This one closes tabs through the per-tab path, so the
  /// user's layout survives.
  closeAllTabs,

  /// Pro-tier action that opens the cross-project
  /// violation-search dialog. Cmd/Ctrl+Shift+F, matching SimCrux; menu
  /// / palette, never the toolbar. Searches every open project's
  /// violations by ruleId / message / filePath / signal substring.
  /// Open-core raises the Pro-gated snack.
  searchAcrossProjects;

  // ─── CruxAction interface implementation ───────────────────────────

  @override
  String get id => 'lintcrux.$name';

  @override
  ActionCategory get category => switch (this) {
    LintcruxAction.openProject => ActionCategory.file,
    LintcruxAction.openSources => ActionCategory.file,
    LintcruxAction.importVivadoFilelist => ActionCategory.file,
    LintcruxAction.importEdam => ActionCategory.file,
    LintcruxAction.quit => ActionCategory.app,
    LintcruxAction.runAllEngines => ActionCategory.tools,
    LintcruxAction.cancelRun => ActionCategory.tools,
    LintcruxAction.toggleTheme => ActionCategory.view,
    // VS Code lists the palette opener at the top of View; the suite
    // follows it, and every surface reads this one category.
    LintcruxAction.openCommandPalette => ActionCategory.view,
    LintcruxAction.focusSearch => ActionCategory.search,
    LintcruxAction.openSettings => ActionCategory.app,
    LintcruxAction.resetWorkspace => ActionCategory.file,
    LintcruxAction.saveSession => ActionCategory.file,
    LintcruxAction.openSession => ActionCategory.file,
    LintcruxAction.importSarif => ActionCategory.file,
    // Exports write a file, so they sit in File next to Save Session —
    // where WaveCrux and NetCrux already put theirs. They were the only
    // exports in the suite living under Tools.
    LintcruxAction.exportSarif => ActionCategory.file,
    LintcruxAction.exportJson => ActionCategory.file,
    LintcruxAction.exportCsv => ActionCategory.file,
    LintcruxAction.exportHtml => ActionCategory.file,
    LintcruxAction.openTabDiagnostics => ActionCategory.tools,
    LintcruxAction.openAppDiagnostics => ActionCategory.tools,
    LintcruxAction.saveFilterPreset => ActionCategory.view,
    LintcruxAction.manageFilterPresets => ActionCategory.view,
    LintcruxAction.openAbout => ActionCategory.help,
    LintcruxAction.checkForUpdates => ActionCategory.help,
    LintcruxAction.submitIssue => ActionCategory.help,
    LintcruxAction.openDocumentation => ActionCategory.help,
    // Workspace / pane / tab actions.
    LintcruxAction.newWorkspace => ActionCategory.file,
    LintcruxAction.saveWorkspaceAs => ActionCategory.file,
    LintcruxAction.openWorkspace => ActionCategory.file,
    LintcruxAction.splitPaneRight => ActionCategory.view,
    LintcruxAction.closePane => ActionCategory.view,
    LintcruxAction.focusOtherPane => ActionCategory.view,
    LintcruxAction.moveTabToOtherPane => ActionCategory.view,
    LintcruxAction.newTab => ActionCategory.file,
    LintcruxAction.closeTab => ActionCategory.file,
    LintcruxAction.nextTab => ActionCategory.view,
    LintcruxAction.previousTab => ActionCategory.view,
    // Cross-probe is a panel, so it sits in View with the other panel
    // toggles — the suite's flagship cross-product feature was in a
    // different menu in half the products.
    LintcruxAction.openCrossProbePanel => ActionCategory.view,
    // Managed-waiver review screen. Lives under Tools
    // alongside the other developer-facing surfaces (the platform
    // menu builds a dedicated "Lint" section in Pro, but the
    // cross-suite category mapping keeps it under Tools so generic
    // command-palette consumers group it with diagnostics and
    // exports rather than File or View.
    LintcruxAction.openWaiverReview => ActionCategory.tools,
    // Baseline & delta actions. Same Tools category as
    // the waiver review screen — they belong with the developer-
    // facing diagnostic surfaces rather than File or View.
    LintcruxAction.setBaseline => ActionCategory.tools,
    LintcruxAction.clearBaseline => ActionCategory.tools,
    LintcruxAction.openBaselineComparison => ActionCategory.tools,
    // Trend tracking surfaces sit under Tools alongside
    // the other developer-facing diagnostic surfaces.
    LintcruxAction.showRuleTrendChart => ActionCategory.tools,
    LintcruxAction.showSeverityClassDriftChart => ActionCategory.tools,
    LintcruxAction.showProjectTrendChart => ActionCategory.tools,
    LintcruxAction.showCalendarHeatmap => ActionCategory.tools,
    LintcruxAction.configureTrendRetention => ActionCategory.tools,
    // Filter presets sit under View (they affect what the
    // violations table shows); bookmarks sit under Tools alongside
    // the other developer-facing surfaces.
    LintcruxAction.openBookmarksManager => ActionCategory.tools,
    LintcruxAction.toggleBookmarkForCurrentViolation => ActionCategory.tools,
    // Verible auto-fix integration. Lives under
    // Tools alongside the other developer-facing diagnostic
    // surfaces.
    LintcruxAction.runVeribleDryRun => ActionCategory.tools,
    LintcruxAction.applyVeribleFixes => ActionCategory.tools,
    // Tools, not app: these two are feature configuration, and the macOS
    // application menu is reserved for About / Settings / Quit.
    LintcruxAction.configureVeribleBinary => ActionCategory.tools,
    // Lint run caching surfaces sit under Tools alongside the other
    // developer-facing surfaces; the Settings entry-point variant is App
    // because it opens the Settings screen.
    LintcruxAction.clearLintCache => ActionCategory.tools,
    LintcruxAction.openLintCacheStats => ActionCategory.tools,
    LintcruxAction.forceLintRunWithoutCache => ActionCategory.tools,
    // Multi-project workspace actions live under
    // File alongside open/close/reset workspace; pin/closeAll are
    // also workspace-management actions; cross-project search is
    // a search surface.
    LintcruxAction.closeActiveProject => ActionCategory.file,
    LintcruxAction.switchProject => ActionCategory.file,
    LintcruxAction.reopenRecentProject => ActionCategory.file,
    LintcruxAction.pinActiveProject => ActionCategory.file,
    LintcruxAction.closeAllProjects => ActionCategory.file,
    LintcruxAction.closeAllTabs => ActionCategory.file,
    LintcruxAction.searchAcrossProjects => ActionCategory.search,
  };
}

/// Maps a [LintcruxAction] to the minimum [LicenseTier] required to
/// activate it. Lives alongside the enum because tier is a Pro /
/// Enterprise concept and the cross-suite [CruxAction] interface
/// deliberately stays tier-agnostic.
///
/// Actions default to [LicenseTier.openCore] (no badge). Only the
/// small set of Pro / Enterprise actions returns a higher tier — the
/// command palette / menu bar renders a `LintCruxFeatureTierBadge` beside the
/// label when the required tier is `pro` or `enterprise`.
///
/// Convention: when adding a new Pro / Enterprise action, *also* add
/// the mapping below in the same commit so the badge renders from
/// day one. Mirrors the WaveCrux / NetCrux pattern.
extension LintcruxActionRequiredTier on LintcruxAction {
  /// Minimum [LicenseTier] needed to activate this action.
  LicenseTier get requiredTier {
    switch (this) {
      case LintcruxAction.openWaiverReview:
        // The managed-waiver review screen is the Pro headline
        // surface for the waiver workflow.
        return LicenseTier.pro;
      case LintcruxAction.setBaseline:
      case LintcruxAction.clearBaseline:
      case LintcruxAction.openBaselineComparison:
        // Baseline & delta is a Pro feature.
        return LicenseTier.pro;
      case LintcruxAction.showRuleTrendChart:
      case LintcruxAction.showSeverityClassDriftChart:
      case LintcruxAction.showProjectTrendChart:
      case LintcruxAction.showCalendarHeatmap:
      case LintcruxAction.configureTrendRetention:
        // Trend tracking is a Pro feature.
        return LicenseTier.pro;
      case LintcruxAction.runVeribleDryRun:
      case LintcruxAction.applyVeribleFixes:
      case LintcruxAction.configureVeribleBinary:
        // Verible auto-fix integration is a Pro feature. The dry-run + apply
        // path shells out to the user's installed Verible binary.
        return LicenseTier.pro;
      case LintcruxAction.clearLintCache:
      case LintcruxAction.openLintCacheStats:
      case LintcruxAction.forceLintRunWithoutCache:
        // Lint run caching is a Pro feature. Open-core ships the seam + no-op
        // so the runner integration is unconditional; the SQLite-backed
        // persistence + cache-management UI is Pro.
        return LicenseTier.pro;
      case LintcruxAction.openBookmarksManager:
      case LintcruxAction.toggleBookmarkForCurrentViolation:
        // User-authored filter-preset persistence + violation bookmarks are a
        // Pro feature. The open-core build still ships the three built-in
        // presets but saving / editing / managing user presets + bookmarking
        // individual violations require Pro.
        return LicenseTier.pro;
      case LintcruxAction.pinActiveProject:
      case LintcruxAction.closeAllProjects:
      case LintcruxAction.searchAcrossProjects:
      case LintcruxAction.switchProject:
      case LintcruxAction.reopenRecentProject:
        // The multi-project registry is a Pro feature in every product
        // that has one. Open-core ships
        // [NoopProjectRegistry]: one project, recents cleared by
        // construction, pinning a silent no-op. Pin, close-all-but-pinned,
        // cross-project search, switching between open projects, and
        // reopening a recent all resolve to nothing under that default,
        // so all five carry the PRO badge. `openProject` and
        // `closeActiveProject` stay open-core — they work standalone.
        return LicenseTier.pro;
      case LintcruxAction.openProject:
      case LintcruxAction.openSources:
      case LintcruxAction.importVivadoFilelist:
      case LintcruxAction.importEdam:
      case LintcruxAction.quit:
      case LintcruxAction.runAllEngines:
      case LintcruxAction.cancelRun:
      case LintcruxAction.toggleTheme:
      case LintcruxAction.openCommandPalette:
      case LintcruxAction.focusSearch:
      case LintcruxAction.openSettings:
      case LintcruxAction.resetWorkspace:
      case LintcruxAction.saveSession:
      case LintcruxAction.openSession:
      case LintcruxAction.importSarif:
      case LintcruxAction.exportSarif:
      case LintcruxAction.exportJson:
      case LintcruxAction.exportCsv:
      case LintcruxAction.exportHtml:
      case LintcruxAction.openTabDiagnostics:
      case LintcruxAction.openAppDiagnostics:
      case LintcruxAction.saveFilterPreset:
      case LintcruxAction.manageFilterPresets:
      case LintcruxAction.openAbout:
      case LintcruxAction.checkForUpdates:
      case LintcruxAction.submitIssue:
      case LintcruxAction.openDocumentation:
      case LintcruxAction.newWorkspace:
      case LintcruxAction.saveWorkspaceAs:
      case LintcruxAction.openWorkspace:
      case LintcruxAction.splitPaneRight:
      case LintcruxAction.closePane:
      case LintcruxAction.focusOtherPane:
      case LintcruxAction.moveTabToOtherPane:
      case LintcruxAction.newTab:
      case LintcruxAction.closeTab:
      case LintcruxAction.nextTab:
      case LintcruxAction.previousTab:
      case LintcruxAction.openCrossProbePanel:
      case LintcruxAction.closeActiveProject:
      // Closing every workspace tab works standalone under
      // [NoopProjectRegistry] — no registry, no pinning — so it stays
      // open-core alongside `openProject` / `closeActiveProject`.
      // SimCrux classifies its `closeAllTabs` the same way.
      case LintcruxAction.closeAllTabs:
        return LicenseTier.openCore;
    }
  }
}

/// Flutter [Intent] dispatched when a [LintcruxAction] keyboard shortcut
/// fires.
///
/// `Actions.maybeInvoke<ShortcutActionIntent>(context, ShortcutActionIntent(a))`
/// dispatches the intent up the widget tree until an [Actions] widget
/// returns a non-null result. The shortcut-manager widget registers a
/// single [CallbackAction] that fans the intent out to the
/// product-supplied handler map; context-sensitive areas (waveform
/// canvas, violation table) may register their own [Actions] wrappers to
/// intercept specific actions higher in the tree.
@immutable
class ShortcutActionIntent extends Intent {
  /// Creates an intent wrapping [action].
  const ShortcutActionIntent(this.action);

  /// The action that fired.
  final LintcruxAction action;
}
