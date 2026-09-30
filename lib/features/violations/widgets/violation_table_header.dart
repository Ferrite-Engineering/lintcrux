// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/plugins/violation_row_leading_cells_provider.dart';

/// Sortable column header row above the virtualized violation list.
///
/// Click any header to sort by that column; click the active sort
/// header again to flip the direction.
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
    Widget cell(String label, ViolationTableColumn col, int flex) {
      final isActive = state.sortColumn == col;
      return Expanded(
        flex: flex,
        // A header cell is a control (it sorts), so it is announced as a
        // button; a bare InkWell carries the tap action but no role, and a
        // screen reader called each header plain "text".
        child: Semantics(
          button: true,
          child: InkWell(
            key: ValueKey('violationTableHeader-${col.name}'),
            onTap: () => notifier.cycleSort(col),
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
                        state.sortAscending
                            ? Icons.arrow_drop_up
                            : Icons.arrow_drop_down,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
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
          cell(l10n.violationColumnSeverity, ViolationTableColumn.severity, 1),
          cell(l10n.violationColumnEngine, ViolationTableColumn.engine, 1),
          cell(l10n.violationColumnRule, ViolationTableColumn.rule, 2),
          cell(l10n.violationColumnFile, ViolationTableColumn.file, 3),
          cell(l10n.violationColumnLine, ViolationTableColumn.line, 1),
          cell(l10n.violationColumnMessage, ViolationTableColumn.message, 5),
        ],
      ),
    );
  }
}
