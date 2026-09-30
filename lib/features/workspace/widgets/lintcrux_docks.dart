// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_dock/crux_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/features/inspector/widgets/inspector_pane.dart';
import 'package:lintcrux/features/remote/widgets/cross_probe_panel.dart';
import 'package:lintcrux/features/rules/widgets/rules_panel.dart';
import 'package:lintcrux/features/source_preview/widgets/source_preview_pane.dart';
import 'package:lintcrux/features/sources/widgets/sources_panel.dart';
import 'package:lintcrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:lintcrux/features/viewer/providers/right_dock_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// LintCrux's right dock: Details (pinned) · Cross-Probe (on-demand).
///
/// This brings the CXP panel *inside* the IDE layout. It used to be bolted
/// onto a Row beside the whole pane host — fixed 320 px, not resizable, the
/// only panel in the suite living outside its app's layout system. As a dock
/// tab it shares the right region's splitter, collapse, and chrome with
/// Details, exactly like WaveCrux and NetCrux.
class LintcruxRightDock extends ConsumerWidget {
  /// Creates the right dock.
  const LintcruxRightDock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final tabNotifier = ref.read(rightDockTabProvider.notifier);

    return CruxDock(
      entries: [
        CruxDockEntry(
          id: kRightDockTabDetails,
          icon: Icons.info_outline,
          label: l10n.dockTabDetails,
          builder: (_) => const InspectorPane(),
        ),
        ..._crossProbeEntry(context, ref, region: kDockRegionRight),
      ],
      activeId: ref.watch(effectiveRightDockTabProvider),
      onSelect: tabNotifier.select,
      onAutoReveal: tabNotifier.reveal,
      dockId: kDockRegionRight,
      onTabMovedIn: (id, _) => _moveTab(ref, id, kDockRegionRight),
      onCollapse: () => ref
          .read(panelLayoutProvider.notifier)
          .setViolationDetailsVisible(visible: false),
      collapseTooltip: l10n.dockCollapseTooltip,
      collapseDirection: CruxDockCollapseDirection.right,
      semanticsLabel: l10n.accessibilityRightDockRegion,
    );
  }
}

/// LintCrux's left dock: Sources · Rules.
///
/// Sources leads because it is the only place a project's contents are
/// visible. Adding a source used to be a one-way door — the picker appended
/// to the project and nothing listed what the project held, so a wrong file
/// could only be undone by editing `.lintcrux` by hand.
class LintcruxLeftDock extends ConsumerWidget {
  /// Creates the left dock.
  const LintcruxLeftDock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    return CruxDock(
      entries: [
        CruxDockEntry(
          id: 'sources',
          icon: Icons.description_outlined,
          label: l10n.dockTabSources,
          builder: (_) => const SourcesPanel(),
        ),
        CruxDockEntry(
          id: 'rules',
          icon: Icons.rule,
          label: l10n.dockTabRules,
          builder: (_) => const RulesPanel(),
        ),
      ],
      activeId: ref.watch(leftDockTabProvider),
      onSelect: (id) => ref.read(leftDockTabProvider.notifier).select(id),
      onCollapse: () => ref
          .read(panelLayoutProvider.notifier)
          .setRuleBrowserVisible(visible: false),
      collapseTooltip: l10n.dockCollapseTooltip,
      collapseDirection: CruxDockCollapseDirection.left,
      semanticsLabel: l10n.accessibilityLeftDockRegion,
    );
  }
}

/// LintCrux's bottom dock: the source-preview pane, pinned — a "Source"
/// titled header via the auto-hiding strip.
class LintcruxBottomDock extends ConsumerWidget {
  /// Creates the bottom dock.
  const LintcruxBottomDock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    return CruxDock(
      entries: [
        CruxDockEntry(
          id: 'source',
          icon: Icons.code,
          label: l10n.dockTabSource,
          builder: (_) => const SourcePreviewPane(),
        ),
        // A CXP tab dragged down from the right dock.
        ..._crossProbeEntry(context, ref, region: kDockRegionBottom),
      ],
      activeId: ref.watch(bottomDockTabProvider),
      onSelect: (id) => ref.read(bottomDockTabProvider.notifier).select(id),
      dockId: kDockRegionBottom,
      onTabMovedIn: (id, _) => _moveTab(ref, id, kDockRegionBottom),
      onCollapse: () => ref
          .read(panelLayoutProvider.notifier)
          .setRunLogVisible(visible: false),
      collapseTooltip: l10n.dockCollapseTooltip,
      semanticsLabel: l10n.accessibilityBottomDockRegion,
    );
  }
}

/// The movable CXP entry when it is placed in [region] and the feature is
/// on. Shared by both docks so the tab can never render twice.
List<CruxDockEntry> _crossProbeEntry(
  BuildContext context,
  WidgetRef ref, {
  required String region,
}) {
  final l10n = L10N.of(context);
  final visible = ref.watch(
    panelLayoutProvider.select((s) => s.crossProbeVisible),
  );
  if (!visible || ref.watch(crossProbeDockRegionProvider) != region) {
    return const [];
  }
  return [
    CruxDockEntry(
      id: kRightDockTabCrossProbe,
      icon: Icons.sensors_outlined,
      label: l10n.dockTabCrossProbe,
      movable: true,
      builder: (_) => const LintCruxCrossProbePanel(),
      onClose: () => ref
          .read(panelLayoutProvider.notifier)
          .setCrossProbeVisible(visible: false),
    ),
  ];
}

/// Drop handler: re-home [id] into [region] and reveal it there.
void _moveTab(WidgetRef ref, String id, String region) {
  ref.read(crossProbeDockRegionProvider.notifier).move(region);
  if (region == kDockRegionBottom) {
    ref.read(bottomDockTabProvider.notifier).reveal(id);
  } else {
    ref.read(rightDockTabProvider.notifier).reveal(id);
  }
}

/// Wraps the IDE layout with the JetBrains-style collapsed-region restore
/// bars (suite panel-reopen model): a hidden region leaves a slim strip of
/// its tab icons along its window edge; a click reopens the region with
/// that tab active.
class LintcruxDockRestoreBars extends ConsumerWidget {
  /// Creates the wrapper. [child] is the `CruxIdeLayout`.
  const LintcruxDockRestoreBars({required this.child, super.key});

  /// The IDE layout being wrapped.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final layout = ref.watch(panelLayoutProvider);
    final notifier = ref.read(panelLayoutProvider.notifier);

    final showLeft = !layout.ruleBrowserVisible;
    final showRight = !layout.violationDetailsVisible;
    final showBottom = !layout.runLogVisible;

    // One tree shape whatever is collapsed -- picking the wrapper widget by
    // which regions were collapsed (the bare child, a Column, a Row, a Row
    // around a Column) changed the widget type directly above the IDE
    // layout on every dock toggle, so Flutter discarded and rebuilt the
    // whole layout: every dock, the pane scope, the show/hide animation,
    // and dock scroll positions. See WaveCrux's dock_restore_bars.dart for
    // the incident this mirrors. The bars are keyed so one appearing or
    // vanishing is matched by identity and touches nothing but itself.
    return Row(
      children: [
        if (showLeft)
          CruxDockRestoreBar(
            key: const ValueKey('dockRestoreBar.left'),
            edge: CruxDockCollapseDirection.left,
            entries: [
              CruxDockRestoreEntry(
                id: 'rules',
                icon: Icons.rule,
                label: l10n.dockTabRules,
                onRestore: () => notifier.setRuleBrowserVisible(visible: true),
              ),
            ],
            semanticsLabel: l10n.accessibilityLeftDockRegion,
          ),
        Expanded(
          key: const ValueKey('dockRestoreBars.center'),
          child: Column(
            children: [
              Expanded(child: child),
              if (showBottom)
                CruxDockRestoreBar(
                  key: const ValueKey('dockRestoreBar.bottom'),
                  edge: CruxDockCollapseDirection.down,
                  entries: [
                    CruxDockRestoreEntry(
                      id: 'source',
                      icon: Icons.code,
                      label: l10n.dockTabSource,
                      onRestore: () => notifier.setRunLogVisible(visible: true),
                    ),
                    for (final entry in _crossProbeEntry(
                      context,
                      ref,
                      region: kDockRegionBottom,
                    ))
                      CruxDockRestoreEntry(
                        id: entry.id,
                        icon: entry.icon,
                        label: entry.label,
                        onRestore: () => ref
                            .read(bottomDockTabProvider.notifier)
                            .reveal(entry.id),
                      ),
                  ],
                  semanticsLabel: l10n.accessibilityBottomDockRegion,
                ),
            ],
          ),
        ),
        if (showRight)
          CruxDockRestoreBar(
            key: const ValueKey('dockRestoreBar.right'),
            edge: CruxDockCollapseDirection.right,
            entries: [
              CruxDockRestoreEntry(
                id: kRightDockTabDetails,
                icon: Icons.info_outline,
                label: l10n.dockTabDetails,
                onRestore: () => ref
                    .read(rightDockTabProvider.notifier)
                    .reveal(kRightDockTabDetails),
              ),
              for (final entry in _crossProbeEntry(
                context,
                ref,
                region: kDockRegionRight,
              ))
                CruxDockRestoreEntry(
                  id: entry.id,
                  icon: entry.icon,
                  label: entry.label,
                  onRestore: () =>
                      ref.read(rightDockTabProvider.notifier).reveal(entry.id),
                ),
            ],
            semanticsLabel: l10n.accessibilityRightDockRegion,
          ),
      ],
    );
  }
}
