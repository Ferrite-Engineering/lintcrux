// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_table/crux_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';
import 'package:lintcrux/features/violations/providers/violation_column_layout_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/plugins/violation_row_leading_cells_provider.dart';

/// Sortable column header row above the virtualized violation list.
///
/// Click any header to sort by that column; click the active sort
/// header again to flip the direction. Drag the divider on a header's right
/// edge to resize that column against its neighbour; double-click a divider
/// to restore the default widths. The widths come from
/// [violationColumnLayoutProvider], which the rows read too.
///
/// The chrome and the dividers are `crux_table`'s ([CruxTableHeader]); this
/// widget supplies the columns, their labels, the sort state and the
/// overlay's leading cells. The cells keep the `violationTableHeader-<column>`
/// keys and the dividers the `violationTableResize-<column>` keys the tests
/// find them by.
///
/// The cell itself is [_SortableHeaderCell], LintCrux's reading of
/// `CruxSortableHeaderCell` with one difference: the sort arrow's slot
/// shrinks in a column narrower than the arrow. The shared cell gives the
/// arrow a fixed 18 dp slot, and in a pane squeezed to ~450 px the sorted
/// column (Severity at its default weight is 25 px wide there) overflows by
/// the difference, which the squeezed-pane test catches as a RenderFlex
/// error. Returns to the shared cell once crux-shared#33 lands.
class ViolationTableHeader extends ConsumerWidget {
  /// Creates a [ViolationTableHeader].
  const ViolationTableHeader({super.key});

  /// The table's name: the prefix of every header and divider key.
  static const String tableId = 'violationTable';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final state = ref.watch(violationTableStateProvider);
    final notifier = ref.read(violationTableStateProvider.notifier);
    final leadingCells = ref.watch(violationRowLeadingCellsProvider);
    final layout = ref.watch(violationColumnLayoutProvider);
    return CruxTableHeader<ViolationTableColumn>(
      tableId: tableId,
      layout: layout,
      controller: ref.read(violationColumnLayoutProvider.notifier),
      leading: [
        // Selection checkbox spacer (24 dp).
        const SizedBox(width: 32),
        for (final lc in leadingCells)
          SizedBox(
            width: lc.width,
            child: Builder(builder: (ctx) => lc.headerBuilder(ctx, ref)),
          ),
      ],
      cellBuilder: (context, column) => _SortableHeaderCell(
        key: cruxTableHeaderKey(tableId, column),
        label: _label(l10n, column),
        sorted: state.sortColumn == column,
        ascending: state.sortAscending,
        onTap: () => notifier.cycleSort(column),
      ),
    );
  }

  static String _label(L10N l10n, ViolationTableColumn column) =>
      switch (column) {
        ViolationTableColumn.severity => l10n.violationColumnSeverity,
        ViolationTableColumn.engine => l10n.violationColumnEngine,
        ViolationTableColumn.rule => l10n.violationColumnRule,
        ViolationTableColumn.file => l10n.violationColumnFile,
        ViolationTableColumn.line => l10n.violationColumnLine,
        ViolationTableColumn.message => l10n.violationColumnMessage,
      };
}

/// A header cell that sorts its column when activated: `crux_table`'s
/// `CruxSortableHeaderCell` (button semantics, the ellipsizing label, the
/// arrow on the sorted column only, the shared padding and arrow size), with
/// the arrow's slot bounded by the cell. "Crop, don't crush": a column
/// squeezed below the arrow's width shows as much of the arrow as fits
/// instead of overflowing the row. See [ViolationTableHeader].
class _SortableHeaderCell extends StatelessWidget {
  const _SortableHeaderCell({
    required this.label,
    required this.onTap,
    required this.sorted,
    required this.ascending,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final bool sorted;
  final bool ascending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    // A header cell is a control (it sorts), so it is announced as a
    // button; a bare InkWell carries the tap action but no role, and a
    // screen reader called each header plain "text".
    return Semantics(
      button: true,
      container: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: kCruxTableCellPadding,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final arrowSlot = sorted
                  ? kCruxTableSortArrowSize.clamp(0.0, constraints.maxWidth)
                  : 0.0;
              return Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (sorted)
                    SizedBox(
                      width: arrowSlot,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Icon(
                          ascending
                              ? Icons.arrow_drop_up
                              : Icons.arrow_drop_down,
                          size: kCruxTableSortArrowSize,
                          color: color,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
