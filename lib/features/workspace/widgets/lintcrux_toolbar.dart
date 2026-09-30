// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_toolbar/crux_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/core/shortcuts/action_category.dart';
import 'package:lintcrux/core/shortcuts/action_label.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_context.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_descriptor.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_descriptors.dart';
import 'package:lintcrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:lintcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:lintcrux/features/viewer/providers/right_dock_provider.dart';
import 'package:lintcrux/features/workspace/providers/lintcrux_action_context_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// LintCrux's binding of the shared [CruxToolbar] to its own action catalog.
///
/// Everything structural — geometry, the `[common] │ [specific]` split, the
/// overflow slot and its edge fade, live-binding tooltips, per-action keys and
/// the semantics region — lives in `crux_toolbar`.
///
/// Two defects go away with the migration:
///
/// - The old strip drew its rule on the **top** edge, left over from a doc
///   comment claiming it was an `AppBar.bottom` band (it never was, and the
///   vestigial `implements PreferredSizeWidget` went with it). Every other
///   product's toolbar rules the bottom.
/// - Every button was unconditionally live. With no project open, `Run All
///   Engines`, `Cancel Run` and `Find in Violations…` were all clickable and
///   silently did nothing. Enablement now comes from the descriptor table,
///   the same source the menu bar and palette read.
class LintcruxToolbar extends ConsumerWidget {
  /// Creates the LintCrux toolbar.
  const LintcruxToolbar({super.key});

  void _dispatch(BuildContext context, LintcruxAction action) =>
      Actions.maybeInvoke<ShortcutActionIntent>(
        context,
        ShortcutActionIntent(action),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final ctx = ref.watch(lintcruxActionContextProvider);
    final bindings = ref.watch(shortcutBindingsProvider);
    // Dock-aware glyph: lit only when the CXP tab is the one on screen.
    final crossProbeVisible = ref.watch(crossProbeShowingProvider);
    final peerCount = ref.watch(cxpPeersProvider).length;

    return CruxToolbar<LintcruxAction>(
      common: [
        CruxToolbarButtonItem(
          action: LintcruxAction.openProject,
          icon: Icons.folder_open_outlined,
          tooltip: LintcruxAction.openProject.label(l10n),
        ),
        CruxToolbarButtonItem(
          action: LintcruxAction.saveSession,
          icon: Icons.save_outlined,
          tooltip: LintcruxAction.saveSession.label(l10n),
        ),
        CruxToolbarButtonItem(
          action: LintcruxAction.closeActiveProject,
          icon: Icons.close,
          tooltip: LintcruxAction.closeActiveProject.label(l10n),
        ),
        const CruxToolbarSeparatorItem(),
        CruxToolbarButtonItem(
          action: LintcruxAction.focusSearch,
          icon: Icons.search,
          tooltip: LintcruxAction.focusSearch.label(l10n),
        ),
        CruxToolbarButtonItem(
          action: LintcruxAction.openCrossProbePanel,
          icon: Icons.sensors_outlined,
          selectedIcon: Icons.sensors,
          isSelected: crossProbeVisible,
          badgeCount: peerCount,
          tooltip: l10n.toolbarToggleCrossProbe,
        ),
        CruxToolbarButtonItem(
          action: LintcruxAction.openSettings,
          icon: Icons.settings_outlined,
          tooltip: LintcruxAction.openSettings.label(l10n),
        ),
      ],
      specific: [
        // Leads the specific block, which is where NetCrux puts the
        // equivalent `openSourceFiles`, with the same glyph. The action
        // existed and was reachable only from the menu and the palette,
        // so the one file verb a user needs *after* opening a project had
        // no button.
        CruxToolbarButtonItem(
          action: LintcruxAction.openSources,
          icon: Icons.note_add_outlined,
          tooltip: LintcruxAction.openSources.label(l10n),
        ),
        // Stays in `specific` rather than moving up beside Open Project.
        // `common` is the suite-canonical block — all four products draw
        // the same seven slots there, and LintCrux's already match — so an
        // eighth LintCrux-only item would break the one part of the strip
        // that exists to be identical everywhere. What was actually wrong
        // was the glyph: `Icons.workspaces_outlined` is the "workspaces"
        // cluster mark and reads as a mode toggle, which is why this did
        // not register as a file action at all. `folder_special_outlined`
        // keeps Open Project's folder verb and changes only the noun.
        CruxToolbarButtonItem(
          action: LintcruxAction.openWorkspace,
          icon: Icons.folder_special_outlined,
          tooltip: LintcruxAction.openWorkspace.label(l10n),
        ),
        CruxToolbarButtonItem(
          action: LintcruxAction.importSarif,
          icon: Icons.file_download_outlined,
          tooltip: LintcruxAction.importSarif.label(l10n),
        ),
        const CruxToolbarSeparatorItem(),
        // One control that *is* the run state, replacing the Run and Cancel
        // buttons that used to sit side by side, both permanently lit, so the
        // toolbar never said whether a lint run was in flight.
        CruxToolbarWidgetItem(
          id: 'run-stop',
          child: _RunStopButton(
            ctx: ctx,
            onAction: (a) => _dispatch(context, a),
          ),
        ),
        const CruxToolbarSeparatorItem(),
        // The four export formats were menu-only and would never each earn a
        // slot; grouped, they earn one.
        CruxToolbarSplitItem(
          id: 'export',
          tooltip: l10n.toolbarExportCluster,
          variants: [
            CruxToolbarButtonItem(
              action: LintcruxAction.exportSarif,
              icon: Icons.upload_file_outlined,
              tooltip: LintcruxAction.exportSarif.label(l10n),
            ),
            CruxToolbarButtonItem(
              action: LintcruxAction.exportJson,
              icon: Icons.data_object,
              tooltip: LintcruxAction.exportJson.label(l10n),
            ),
            CruxToolbarButtonItem(
              action: LintcruxAction.exportCsv,
              icon: Icons.table_chart_outlined,
              tooltip: LintcruxAction.exportCsv.label(l10n),
            ),
            CruxToolbarButtonItem(
              action: LintcruxAction.exportHtml,
              icon: Icons.html_outlined,
              tooltip: LintcruxAction.exportHtml.label(l10n),
            ),
          ],
        ),
      ],
      isEnabled: (action) => isActionEnabled(action, ctx),
      onAction: (action) => _dispatch(context, action),
      shortcutOf: (action) => bindings[action],
      semanticsLabel: l10n.accessibilityToolbarRegion,
      overflow: CruxToolbarOverflowMenu<LintcruxAction>(
        groups: [
          for (final entry in groupedActionsFor(
            LintcruxActionSurface.menu,
            ctx,
          ).entries)
            if (entry.key != ActionCategory.app)
              CruxOverflowGroup<LintcruxAction>(
                label: entry.key.label(l10n),
                actions: entry.value,
              ),
        ],
        labelOf: (action) => action.label(l10n),
        isEnabled: (action) => isActionEnabled(action, ctx),
        shortcutOf: (action) => bindings[action],
        onAction: (action) => _dispatch(context, action),
        tooltip: l10n.toolbarOverflowActions,
      ),
    );
  }
}

/// The morphing run control, wired to the descriptor table's run gates.
class _RunStopButton extends StatelessWidget {
  const _RunStopButton({required this.ctx, required this.onAction});

  final LintcruxActionContext ctx;
  final void Function(LintcruxAction) onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return CruxRunStopButton(
      state: ctx.runInProgress ? CruxRunState.running : CruxRunState.idle,
      metrics: CruxToolbarMetrics.desktop,
      runTooltip: LintcruxAction.runAllEngines.label(l10n),
      cancelTooltip: LintcruxAction.cancelRun.label(l10n),
      onRun: isActionEnabled(LintcruxAction.runAllEngines, ctx)
          ? () => onAction(LintcruxAction.runAllEngines)
          : null,
      onCancel: isActionEnabled(LintcruxAction.cancelRun, ctx)
          ? () => onAction(LintcruxAction.cancelRun)
          : null,
    );
  }
}
