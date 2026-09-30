// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// The state snapshot every action-discovery surface gates on.
///
/// Menu bar, command palette, toolbar, and the keyboard dispatch path all read
/// one of these, so a command greys out identically wherever the user meets
/// it. Before this type LintCrux had **no** enablement at all: every menu item
/// was live regardless of state, so with no project open `Run All Engines`,
/// `Export Violations as SARIF…`, `Set Baseline from Current Run…` and
/// `Close Pane` were all clickable and silently did nothing.
///
/// Workspace-level facts come straight from `workspaceProvider`; the per-tab
/// facts are mirrored up to the root by `activeTabActionFlagsProvider`,
/// because the surfaces evaluate at root scope and cannot watch a tab
/// container's providers directly.
@immutable
class LintcruxActionContext {
  /// Creates a context snapshot. Defaults describe a cold start: no tab, no
  /// project, nothing run, single pane.
  const LintcruxActionContext({
    this.hasOpenTab = false,
    this.hasProject = false,
    this.runInProgress = false,
    this.hasViolations = false,
    this.hasSelectedViolation = false,
    this.paneCount = 1,
    this.tabCountInActivePane = 0,
  });

  /// Whether the workspace has an active tab. Gates everything that reads or
  /// mutates per-tab state — without a tab those handlers resolve the empty
  /// root scope and no-op.
  final bool hasOpenTab;

  /// Whether the active tab has a loaded project / config. Gates the lint
  /// run, the exports, and the baseline and trend surfaces, all of which
  /// operate on a project.
  final bool hasProject;

  /// Whether a lint run is currently executing in the active tab. Gates
  /// Cancel Run *on*, and the run actions *off* — starting a second run over
  /// a running one is not a thing the engines support.
  final bool runInProgress;

  /// Whether the active tab holds at least one violation. Gates the exports
  /// and Set Baseline: writing an empty SARIF file or baselining nothing is
  /// never what the user meant.
  final bool hasViolations;

  /// Whether a violation row is selected in the active tab. Gates the
  /// per-violation commands (bookmark toggle).
  final bool hasSelectedViolation;

  /// How many panes the workspace has. Gates the pane commands.
  final int paneCount;

  /// How many tabs the active pane holds. Gates Next / Previous Tab —
  /// cycling is inert with fewer than two.
  final int tabCountInActivePane;

  @override
  bool operator ==(Object other) =>
      other is LintcruxActionContext &&
      other.hasOpenTab == hasOpenTab &&
      other.hasProject == hasProject &&
      other.runInProgress == runInProgress &&
      other.hasViolations == hasViolations &&
      other.hasSelectedViolation == hasSelectedViolation &&
      other.paneCount == paneCount &&
      other.tabCountInActivePane == tabCountInActivePane;

  @override
  int get hashCode => Object.hash(
    hasOpenTab,
    hasProject,
    runInProgress,
    hasViolations,
    hasSelectedViolation,
    paneCount,
    tabCountInActivePane,
  );
}
