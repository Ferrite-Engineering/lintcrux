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
/// The chrome, the dividers and the sortable cell are `crux_table`'s
/// ([CruxTableHeader], [CruxSortableHeaderCell]); this widget supplies the
/// columns, their labels, the sort state and the overlay's leading cells.
/// The cells keep the `violationTableHeader-<column>` keys and the dividers
/// the `violationTableResize-<column>` keys the tests find them by.
///
/// "Crop, don't crush" holds in a squeezed pane: the shared cell bounds the
/// sort arrow's slot by the cell, so the sorted column in a ~450 px pane
/// (Severity at its default weight is 25 px wide there) crops the arrow
/// instead of overflowing the row. The squeezed-pane test pins it.
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
      cellBuilder: (context, column) => CruxSortableHeaderCell(
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
