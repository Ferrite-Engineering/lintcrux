// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart' show DragStartBehavior;
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
class ViolationTableHeader extends ConsumerWidget {
  /// Creates a [ViolationTableHeader].
  const ViolationTableHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final state = ref.watch(violationTableStateProvider);
    final notifier = ref.read(violationTableStateProvider.notifier);
    final leadingCells = ref.watch(violationRowLeadingCellsProvider);
    final scheme = Theme.of(context).colorScheme;
    final layout = ref.watch(violationColumnLayoutProvider);
    Widget cell(String label, ViolationTableColumn col, double tableWidth) {
      final isActive = state.sortColumn == col;
      final isLast = col == ViolationTableColumn.values.last;
      return Expanded(
        flex: layout.flexOf(col),
        child: Row(
          children: [
            Expanded(
              child: _sortButton(
                context,
                label,
                col,
                isActive: isActive,
                ascending: state.sortAscending,
                onTap: () => notifier.cycleSort(col),
              ),
            ),
            if (!isLast) _ResizeHandle(column: col, tableWidth: tableWidth),
          ],
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          // Selection checkbox spacer (24 dp).
          const SizedBox(width: 32),
          for (final lc in leadingCells)
            SizedBox(
              width: lc.width,
              child: Builder(
                builder: (ctx) => lc.headerBuilder(ctx, ref),
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                return Row(
                  children: [
                    cell(
                      l10n.violationColumnSeverity,
                      ViolationTableColumn.severity,
                      w,
                    ),
                    cell(
                      l10n.violationColumnEngine,
                      ViolationTableColumn.engine,
                      w,
                    ),
                    cell(
                      l10n.violationColumnRule,
                      ViolationTableColumn.rule,
                      w,
                    ),
                    cell(
                      l10n.violationColumnFile,
                      ViolationTableColumn.file,
                      w,
                    ),
                    cell(
                      l10n.violationColumnLine,
                      ViolationTableColumn.line,
                      w,
                    ),
                    cell(
                      l10n.violationColumnMessage,
                      ViolationTableColumn.message,
                      w,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _sortButton(
    BuildContext context,
    String label,
    ViolationTableColumn col, {
    required bool isActive,
    required bool ascending,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    // A header cell is a control (it sorts), so it is announced as a
    // button; a bare InkWell carries the tap action but no role, and a
    // screen reader called each header plain "text".
    return Semantics(
      button: true,
      child: InkWell(
        key: ValueKey('violationTableHeader-${col.name}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isActive)
                // Flexible so the 18-dp sort glyph crops instead of
                // overflowing when a narrow pane squeezes a flex-1
                // cell below the icon's own width ("crop, don't
                // crush"). At normal pane widths the loose fit
                // renders the icon at its intrinsic size, unchanged.
                Flexible(
                  child: Icon(
                    ascending ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The divider on a header cell's right edge: drag it to move width between
/// this column and the next, double-click it to restore the default widths.
///
/// Pointer-only and excluded from semantics. It is not a Tab stop, so the
/// table's keyboard order and what a screen reader announces are unchanged;
/// the default widths keep every column readable without it.
class _ResizeHandle extends ConsumerWidget {
  const _ResizeHandle({required this.column, required this.tableWidth});

  final ViolationTableColumn column;

  /// The width all six columns share, which turns a drag's pixels into
  /// weight.
  final double tableWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(violationColumnLayoutProvider.notifier);
    final color = Theme.of(context).colorScheme.outlineVariant;
    return ExcludeSemantics(
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          key: ValueKey('violationTableResize-${column.name}'),
          behavior: HitTestBehavior.opaque,
          // Count movement from pointer-down, so the divider stays under
          // the cursor instead of lagging by the drag threshold.
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragUpdate: (d) =>
              notifier.resize(column, d.delta.dx, tableWidth),
          onHorizontalDragEnd: (_) => notifier.commit(),
          onDoubleTap: notifier.reset,
          child: SizedBox(
            width: 8,
            height: 24,
            child: Center(
              child: SizedBox(
                width: 1,
                height: 16,
                child: ColoredBox(color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
