// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/features/remote/providers/cross_probe_selection.dart';
import 'package:lintcrux/features/viewer/providers/panel_layout_provider.dart';

/// LintCrux's docked cross-probe panel.
///
/// The shared, bound [CruxCrossProbePanel]: LintCrux supplies only which
/// selection a peer row's send carries (the active tab's selected violation)
/// and how the panel closes. The peers, the unreachable peers, the event log
/// and every send's outcome are the shared runtime's.
///
/// Docked as a `CruxDock` tab by `ViewerScaffold`, which swaps it into a
/// right-hand slot when `PanelLayoutState.crossProbeVisible` is set; the strip
/// already carries the icon, the label and the close button, so the panel
/// draws no header of its own.
class LintCruxCrossProbePanel extends ConsumerWidget {
  /// Creates the docked cross-probe panel.
  const LintCruxCrossProbePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CruxCrossProbePanel(
      // Resolved when a send is pressed: the panel is app-level, so its own
      // `ref` is root and the active tab is looked up then.
      selection: () => activeTabCrossProbeSelection(ref.read),
      onClose: () => ref
          .read(panelLayoutProvider.notifier)
          .setCrossProbeVisible(visible: false),
    );
  }
}
