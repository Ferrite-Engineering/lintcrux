// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/features/remote/providers/cross_probe_selection.dart';
import 'package:lintcrux/plugins/violation_context_menu_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';

/// The "Cross-probe to" item of a violation row's right-click menu.
///
/// Free in every tier, and part of the open core's default menu. Choosing it
/// opens the running peers as a second menu where the row is, one item per
/// product (a product running in several windows nests them), and choosing a
/// peer sends the right-clicked violation. With no peer running the item says
/// so instead, and explains what to start.
ViolationContextMenuEntry buildCrossProbeViolationMenuEntry() =>
    ViolationContextMenuEntry(
      id: 'crossProbeTo',
      labelBuilder: (context) {
        final read = ProviderScope.containerOf(context, listen: false).read;
        final strings = cruxCxpStringsOf(context, read);
        return read(crossProbeTargetsProvider).isEmpty
            ? strings.noPeersRunning
            : strings.crossProbeTo;
      },
      onActivate: (context, ref, violation) async {
        final entry =
            crossProbeMenuEntry(
                  context,
                  ref,
                  selection: () => crossProbeSelectionForViolation(
                    violation,
                    project: ref.read(currentProjectProvider),
                  ),
                )
                as CruxSubmenu;
        if (!entry.enabled) {
          showCruxInfoSnack(context, entry.tooltip ?? entry.label);
          return;
        }
        final box = context.findRenderObject();
        final position = box is RenderBox
            ? box.localToGlobal(box.size.bottomLeft(Offset.zero))
            : Offset.zero;
        await showCruxContextMenu(
          context,
          globalPosition: position,
          entries: entry.entries,
        );
      },
    );
