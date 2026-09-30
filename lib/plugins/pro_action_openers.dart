// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/plugins/pro_opener.dart';

/// Open-core opener seams for Pro / Phase-4 actions that need the Pro
/// overlay to mount a screen, dialog, or run a Pro-only side effect.
///
/// Each opener is a `Provider<ProActionOpener?>` defaulting to `null`.
/// The Pro overlay's `proOverrides` list replaces each provider with
/// the real implementation; in an open-core build the provider stays
/// null and the dispatcher answers the user with a localized snack
/// rather than a silent no-op. See [ProActionOpener] for why the
/// default is `null` and not a no-op function.
///
/// Mirrors the existing seam style (`baselineComparisonOpenerProvider`,
/// `waiverReviewOpenerProvider`, …) — kept in one file because each
/// opener is one line and the dedicated file-per-opener convention
/// from the earlier seams (one screen each) doesn't carry its weight
/// for the post-Phase-4 batch.

// ── Baseline mutators ─────────────────────────────────────────────

/// Snapshots the active tab's currently-visible violations as the
/// next baseline (with a Pro-only confirm dialog + audit log entry).
/// Null in open-core; Pro overrides via `BaselineToolbarActions`'s
/// flow.
final Provider<ProActionOpener?> setBaselineOpenerProvider =
    Provider<ProActionOpener?>(
      (_) => null,
    );

/// Clears the active tab's baseline (with a Pro-only confirm dialog +
/// audit log entry). Null in open-core; Pro overrides.
final Provider<ProActionOpener?> clearBaselineOpenerProvider =
    Provider<ProActionOpener?>(
      (_) => null,
    );

// ── Bookmark ──────────────────────────────────────────────────────

/// Toggles the bookmark for the currently-selected violation (opens
/// the bookmark dialog in create / edit mode as appropriate). Null in
/// open-core; Pro overrides.
final Provider<ProActionOpener?> toggleBookmarkOpenerProvider =
    Provider<ProActionOpener?>(
      (_) => null,
    );

// ── Verible ───────────────────────────────────────────────────────

/// Kicks off a Verible dry-run and opens the FixReviewDialog with the
/// result batch. Null in open-core; Pro overrides.
final Provider<ProActionOpener?> runVeribleDryRunOpenerProvider =
    Provider<ProActionOpener?>((_) => null);

/// Opens the fix review dialog on a fresh dry-run batch. Applying is
/// always user-confirmed from inside that dialog — there is no
/// unattended auto-apply path. Null in open-core; Pro overrides.
final Provider<ProActionOpener?> applyVeribleFixesOpenerProvider =
    Provider<ProActionOpener?>((_) => null);

/// Opens Settings → Verible so the user can configure the
/// `verible-verilog-lint` binary path. Null in open-core; Pro overrides.
final Provider<ProActionOpener?> configureVeribleBinaryOpenerProvider =
    Provider<ProActionOpener?>((_) => null);

// ── Lint cache ────────────────────────────────────────────────────

/// Clears the active project's lint cache (`<projectPath>/.lintcrux/cache.db`).
/// Null in open-core; Pro overrides.
final Provider<ProActionOpener?> clearLintCacheOpenerProvider =
    Provider<ProActionOpener?>(
      (_) => null,
    );

/// Opens the lint cache invalidation log dialog. Null in open-core;
/// Pro overrides.
final Provider<ProActionOpener?> openLintCacheStatsOpenerProvider =
    Provider<ProActionOpener?>((_) => null);

/// Re-runs lint with `forceBypassCache: true` for one invocation,
/// regardless of the user's `lintCacheEnabled` setting. Null in
/// open-core; Pro overrides.
final Provider<ProActionOpener?> forceLintRunWithoutCacheOpenerProvider =
    Provider<ProActionOpener?>((_) => null);

// ── Trend charts ──────────────────────────────────────────────────

/// Opens the per-rule violation trend chart. Null in open-core; Pro
/// overrides.
final Provider<ProActionOpener?> showRuleTrendChartOpenerProvider =
    Provider<ProActionOpener?>((_) => null);

/// Opens the severity-class drift trend chart. Null in open-core; Pro
/// overrides.
final Provider<ProActionOpener?> showSeverityClassDriftChartOpenerProvider =
    Provider<ProActionOpener?>((_) => null);

/// Opens the project-wide trend chart. Null in open-core; Pro overrides.
final Provider<ProActionOpener?> showProjectTrendChartOpenerProvider =
    Provider<ProActionOpener?>((_) => null);

/// Opens the calendar heatmap screen (GitHub-style contributions grid
/// of per-day violation activity). Null in open-core; Pro overrides.
final Provider<ProActionOpener?> showCalendarHeatmapOpenerProvider =
    Provider<ProActionOpener?>((_) => null);

/// Opens Settings → Trend Retention so the user can adjust the
/// trend store's retention policy. Null in open-core; Pro overrides.
final Provider<ProActionOpener?> configureTrendRetentionOpenerProvider =
    Provider<ProActionOpener?>((_) => null);

// ── Project list ops ──────────────────────────────────────────────

/// Toggles the pinned state of the active project tab in the
/// project registry. Null in open-core; Pro overrides.
final Provider<ProActionOpener?> pinActiveProjectOpenerProvider =
    Provider<ProActionOpener?>((_) => null);

/// Closes every open project tab except pinned ones. Null in
/// open-core; Pro overrides.
final Provider<ProActionOpener?> closeAllProjectsOpenerProvider =
    Provider<ProActionOpener?>((_) => null);

/// Opens the project switcher (Cmd/Ctrl+P). Null in open-core, where the
/// registry is `NoopProjectRegistry` and there is nothing to switch
/// between; the Pro overlay mounts the shared `CruxProjectSwitcherDialog`.
final Provider<ProActionOpener?> switchProjectOpenerProvider =
    Provider<ProActionOpener?>((_) => null);

/// Reopens a recently-closed project. Null in open-core (recents are
/// empty by construction under the no-op registry). The Pro overlay
/// routes this to the switcher, which already lists recents with
/// one-click reopen.
final Provider<ProActionOpener?> reopenRecentProjectOpenerProvider =
    Provider<ProActionOpener?>((_) => null);

/// Opens cross-project violation search (Cmd/Ctrl+Shift+F). Null in
/// open-core — with one project there is no "across" to search.
final Provider<ProActionOpener?> searchAcrossProjectsOpenerProvider =
    Provider<ProActionOpener?>((_) => null);
