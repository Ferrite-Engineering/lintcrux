// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_table/crux_table.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';

/// The violation table's resizable columns, left to right, with the weight
/// each starts at.
///
/// Weights rather than pixels: the six columns always share the table's width
/// exactly, so a narrow window never scrolls sideways and a wide one never
/// leaves a gap. Rule is wide enough for a namespaced ID such as
/// `verilator/UNUSEDSIGNAL`, and File, which shows the path relative to the
/// project, needs less than a full path would. The selection check box and
/// an overlay's leading cells are fixed-width and take no part in this.
///
/// The model behind it, `crux_table`'s [CruxTableColumns] and
/// [CruxColumnLayout], is the suite's: resizing moves width between two
/// neighbouring columns and keeps the total, neither neighbour goes below
/// [CruxTableColumns.minColumnWidth], and the widths persist under
/// [kViolationColumnWeightsPrefsKey].
const CruxTableColumns<ViolationTableColumn> violationTableColumns =
    CruxTableColumns<ViolationTableColumn>(
      columns: <ViolationTableColumn>[
        ViolationTableColumn.severity,
        ViolationTableColumn.engine,
        ViolationTableColumn.rule,
        ViolationTableColumn.file,
        ViolationTableColumn.line,
        ViolationTableColumn.message,
      ],
      defaultWeights: <ViolationTableColumn, double>{
        ViolationTableColumn.severity: 1,
        ViolationTableColumn.engine: 1,
        ViolationTableColumn.rule: 2.6,
        ViolationTableColumn.file: 2.2,
        ViolationTableColumn.line: 0.8,
        ViolationTableColumn.message: 5,
      },
    );

/// The violation table's column widths, as relative weights over
/// [violationTableColumns].
typedef ViolationColumnLayout = CruxColumnLayout<ViolationTableColumn>;

/// `SharedPreferences` key holding the saved column weights, as one JSON
/// object of column name to weight. Unchanged since the table's own codec
/// wrote it, so widths saved by an earlier release read back as they were.
const String kViolationColumnWeightsPrefsKey =
    'settings.violationColumnWeights';
