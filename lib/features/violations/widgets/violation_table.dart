// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/violations/widgets/filter_preset_dropdown.dart';
import 'package:lintcrux/features/violations/widgets/violation_filter_chips.dart';
import 'package:lintcrux/features/violations/widgets/violation_row_focus.dart';
import 'package:lintcrux/features/violations/widgets/violation_table_header.dart';
import 'package:lintcrux/features/violations/widgets/violation_table_row.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/plugins/dashboard_banners_provider.dart';
import 'package:lintcrux/plugins/violation_table_top_actions_provider.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';

/// The dashboard centerpiece — virtualized violation list with filter
/// chips above. The live count summary lives in the window-bottom
/// `LintcruxStatusBar`, not here.
///
/// Pipeline:
///
/// - Contributions from `violationTableTopActionsProvider` (a wrapped row)
///   and `dashboardBannersProvider` (full-width notices) sit above the
///   filters; both are empty in the open core.
/// - [ViolationFilterChips] writes to `violationTableStateProvider`,
///   which (combined with the store events) drives
///   `visibleViolationsProvider`.
/// - [ViolationTableHeader] cycles sort columns.
/// - The `ListView.builder` is the virtualized list of
///   [ViolationTableRow]s with a stable [kViolationRowHeight].
///
/// The table carries **no footer summary**. It used to end in a
/// `ViolationStatusBar` rendering `violationStatusSummary` over
/// `visibleViolationsProvider` — the exact string `LintcruxStatusBar` renders
/// at the window bottom, from the same provider, a few hundred pixels below.
/// Two strips saying the same sentence in two typographies is worse than one,
/// so the window-bottom bar (which is the suite-wide surface) is the survivor.
///
/// 50,000-row sets remain interactive because each row is a fixed-
/// height widget and the list uses `itemExtent: kViolationRowHeight`
/// so the framework knows the offset of any index in O(1).
///
/// The rows are one Tab stop ([ViolationRowFocus]): Up, Down, Home and End
/// move between them, and the list says so to a screen reader when focus
/// enters it.
class ViolationTable extends ConsumerStatefulWidget {
  /// Creates a [ViolationTable].
  const ViolationTable({super.key});

  /// Minimum height always reserved for the virtualized list below the
  /// header chrome — three rows, enough to keep the table recognizably
  /// a table even in a heavily squeezed pane.
  static const double _minListHeight = kViolationRowHeight * 3;

  @override
  ConsumerState<ViolationTable> createState() => _ViolationTableState();
}

class _ViolationTableState extends ConsumerState<ViolationTable> {
  final ScrollController _scroll = ScrollController();
  late final ViolationRowFocus _rowFocus = ViolationRowFocus(
    scrollController: _scroll,
    rowExtent: kViolationRowHeight,
  );

  @override
  void dispose() {
    _rowFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final visible = ref.watch(visibleViolationsProvider);
    _rowFocus.sync(visible);
    final store = ref.watch(violationStoreProvider);
    final topActions = ref.watch(violationTableTopActionsProvider);
    final banners = ref.watch(dashboardBannersProvider);
    final header = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FilterPresetDropdown(),
        if (topActions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final builder in topActions)
                  Builder(builder: (ctx) => builder(ctx, ref)),
              ],
            ),
          ),
        // Full-width notices, stacked in list order between the top-action
        // row and the filters. Each renders nothing when it has nothing to
        // say, so an empty list and a list of quiet banners look the same.
        for (final builder in banners)
          Builder(builder: (ctx) => builder(ctx, ref)),
        const ViolationFilterChips(),
        const ViolationTableHeader(),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // "Crop, don't crush" (dock canon): in a narrow pane the
        // filter chrome wraps onto extra runs and can grow taller than
        // the pane itself. Cap the header region so the list always
        // keeps [_minListHeight]; when the cap bites, the header
        // scrolls within its own bounded box instead of overflowing.
        // At normal pane sizes the SingleChildScrollView shrink-wraps
        // to the header's natural height, so nothing changes visually.
        final headerMaxHeight = constraints.hasBoundedHeight
            ? (constraints.maxHeight - ViolationTable._minListHeight).clamp(
                0.0,
                double.infinity,
              )
            : double.infinity;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: headerMaxHeight),
              child: SingleChildScrollView(child: header),
            ),
            Expanded(
              child: visible.isEmpty
                  ? CruxPanelEmptyState(
                      message: store.isEmpty
                          ? l10n.violationStatusEmpty
                          : l10n.violationStatusFiltered,
                    )
                  // The keyboard hint is the list's container label, spoken
                  // once when focus enters the rows.
                  : Semantics(
                      container: true,
                      explicitChildNodes: true,
                      label: l10n.accessibilityViolationTableKeyboardHint,
                      child: ListView.builder(
                        controller: _scroll,
                        itemExtent: kViolationRowHeight,
                        itemCount: visible.length,
                        itemBuilder: (context, i) => ViolationTableRow(
                          key: ValueKey(visible[i]),
                          violation: visible[i],
                          focus: _rowFocus,
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
