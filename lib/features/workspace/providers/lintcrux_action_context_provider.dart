// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_context.dart';
import 'package:lintcrux/features/workspace/providers/active_tab_action_flags_provider.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';

/// Builds the [LintcruxActionContext] every action-discovery surface (menu
/// bar, command palette, toolbar) and the keyboard dispatch path feed to the
/// descriptor selectors in `lintcrux_action_descriptors.dart`. Centralizing it
/// here guarantees all surfaces gate on identical state.
///
/// Workspace-level facts come straight from `workspaceProvider`; the per-tab
/// facts come from the `activeTabActionFlagsProvider` root mirror, because
/// this provider lives at the root scope where per-tab providers resolve to
/// their empty root instances. Tests override this provider directly with a
/// literal context to drive a surface into a precise state.
final lintcruxActionContextProvider = Provider<LintcruxActionContext>((ref) {
  final workspace = ref.watch(workspaceProvider).value;
  final flags = ref.watch(activeTabActionFlagsProvider);
  return LintcruxActionContext(
    hasOpenTab: workspace?.activeTabId != null,
    hasProject: flags.hasProject,
    runInProgress: flags.runInProgress,
    hasViolations: flags.hasViolations,
    hasSelectedViolation: flags.hasSelectedViolation,
    paneCount: workspace?.panes.length ?? 1,
    tabCountInActivePane: workspace == null
        ? 0
        : workspace.tabsForPane(workspace.activePaneId).length,
  );
}, name: 'lintcruxActionContextProvider');
