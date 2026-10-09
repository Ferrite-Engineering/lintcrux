// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';

/// The violation table's column widths, as relative weights.
///
/// Weights rather than pixels: the six columns always share the table's width
/// exactly, so a narrow window never scrolls sideways and a wide one never
/// leaves a gap. Resizing moves width between two neighbouring columns
/// ([resize]), which keeps the total, and so every other column, unchanged.
@immutable
class ViolationColumnLayout {
  /// Creates a layout from [weights]. A column missing from [weights], or
  /// carrying a weight that is not a positive finite number, takes its
  /// default.
  ViolationColumnLayout(Map<ViolationTableColumn, double> weights)
    : weights = Map<ViolationTableColumn, double>.unmodifiable({
        for (final column in ViolationTableColumn.values)
          column: _valid(weights[column]) ?? defaultWeights[column]!,
      });

  /// The layout every table starts with.
  ///
  /// Rule is wide enough for a namespaced ID such as
  /// `verilator/UNUSEDSIGNAL`, and File, which shows the path relative to the
  /// project, needs less than a full path would.
  static const Map<ViolationTableColumn, double> defaultWeights = {
    ViolationTableColumn.severity: 1,
    ViolationTableColumn.engine: 1,
    ViolationTableColumn.rule: 2.6,
    ViolationTableColumn.file: 2.2,
    ViolationTableColumn.line: 0.8,
    ViolationTableColumn.message: 5,
  };

  /// The default layout.
  static final ViolationColumnLayout defaults = ViolationColumnLayout(
    defaultWeights,
  );

  /// The narrowest a column may be dragged, in logical pixels.
  static const double minColumnWidth = 40;

  /// Each column's weight, for every column.
  final Map<ViolationTableColumn, double> weights;

  /// The sum of every column's weight.
  double get totalWeight => weights.values.fold(0, (a, b) => a + b);

  /// The integer flex for [column], fine-grained enough that a one-pixel drag
  /// moves a divider.
  int flexOf(ViolationTableColumn column) =>
      (weights[column]! * 1000).round().clamp(1, 1 << 30);

  /// Moves [dx] logical pixels of width from the column after [column] to
  /// [column] (a negative [dx] moves it the other way), in a table whose
  /// columns span [tableWidth] pixels. Neither column goes below
  /// [minColumnWidth]. Returns this layout when [column] is the last one or
  /// nothing can move.
  ViolationColumnLayout resize(
    ViolationTableColumn column,
    double dx,
    double tableWidth,
  ) {
    final index = column.index;
    if (index >= ViolationTableColumn.values.length - 1 || tableWidth <= 0) {
      return this;
    }
    final next = ViolationTableColumn.values[index + 1];
    final perPixel = totalWeight / tableWidth;
    final minWeight = minColumnWidth * perPixel;
    final pair = weights[column]! + weights[next]!;
    final left = (weights[column]! + dx * perPixel).clamp(
      minWeight,
      pair - minWeight,
    );
    if (pair < 2 * minWeight || left == weights[column]) return this;
    return ViolationColumnLayout({
      ...weights,
      column: left,
      next: pair - left,
    });
  }

  static double? _valid(double? weight) =>
      weight != null && weight.isFinite && weight > 0 ? weight : null;

  @override
  bool operator ==(Object other) =>
      other is ViolationColumnLayout &&
      ViolationTableColumn.values.every((c) => other.weights[c] == weights[c]);

  @override
  int get hashCode =>
      Object.hashAll(ViolationTableColumn.values.map((c) => weights[c]));

  @override
  String toString() => 'ViolationColumnLayout($weights)';
}
