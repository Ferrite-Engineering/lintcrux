// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/violation.dart';

/// One Pro-contributed cell rendered at the leftmost position of each
/// row in the violation table, before the open-core severity / engine /
/// rule / file / line / message columns.
///
/// The violation table renders the contributions returned by
/// [violationRowLeadingCellsProvider] as a horizontal `Row` of fixed-
/// width cells preceding the open-core cells. Each entry is a
/// pre-built widget builder receiving the row's [Violation]; Pro
/// implementations typically build a tier-gated [ConsumerWidget] that
/// reads the violation-bookmark store, queries `lookupByFingerprint`,
/// and renders an outline / filled bookmark icon.
///
/// Mirrors [violationTableTopActionsProvider] in shape so Pro
/// contributions to row chrome feel identical to reviewers. The seam
/// is intentionally narrower than a full column-builder API — leading
/// cells are *prefixes* before the open-core cells, never insertions
/// between them. Inserting a Pro column between the engine and rule
/// columns would require open-core to know about the Pro column's
/// ordering, defeating the open-core / Pro contract.
typedef ViolationRowLeadingCellBuilder =
    Widget Function(
      BuildContext context,
      WidgetRef ref,
      Violation violation,
    );

/// One Pro-contributed leading-cell header rendered in the table
/// header row at the same horizontal slot as its row body
/// counterpart.
///
/// Builders are called inside the header widget's `BuildContext`; Pro
/// implementations typically build a small [Icon] or [Tooltip]
/// matching the body cell's visual weight. Returning a `SizedBox`
/// suppresses the header for cells that need a body-only icon
/// (the bookmark column, for instance, has no header label —
/// the column is identified by its icon).
typedef ViolationRowLeadingCellHeaderBuilder =
    Widget Function(
      BuildContext context,
      WidgetRef ref,
    );

/// One Pro-contributed leading-cell registration: a fixed-width slot
/// claimed by the contributor, plus a row-body builder and a header
/// builder.
///
/// Width must match between header and body to keep the table aligned;
/// the builders read the width to size their internal padding.
@immutable
class ViolationRowLeadingCell {
  /// Creates a leading-cell contribution.
  const ViolationRowLeadingCell({
    required this.id,
    required this.width,
    required this.bodyBuilder,
    required this.headerBuilder,
  });

  /// Stable identifier (used by tests to assert specific contributions
  /// are present without depending on widget identity).
  final String id;

  /// Width in logical pixels claimed by this cell. Mirrors the
  /// width-only checkbox cell on the open-core row (32 dp). Pro
  /// bookmark cells typically reserve 32 dp — enough room for a
  /// 24 dp icon with 4 dp padding on either side, fitting the
  /// existing `kViolationRowHeight` (28 dp) row.
  final double width;

  /// Renders the per-row body cell. Called once per visible row in
  /// the virtualized list.
  final ViolationRowLeadingCellBuilder bodyBuilder;

  /// Renders the header cell at the same slot. Called once per
  /// header rebuild.
  final ViolationRowLeadingCellHeaderBuilder headerBuilder;
}

/// Open-core extension point through which the Pro overlay
/// contributes leading cells (prefixed before the open-core columns)
/// to each row of the violation table.
///
/// Default returns an empty list so the open-core build's violation
/// table renders exactly the open-core columns. The Pro overlay
/// overrides this provider via `proOverrides` with the bookmark
/// column contribution.
///
/// Consumers (the row + header widgets) iterate the list and render
/// each entry's cell at the same horizontal slot, preserving table
/// alignment.
final Provider<List<ViolationRowLeadingCell>> violationRowLeadingCellsProvider =
    Provider<List<ViolationRowLeadingCell>>(
      (_) => const <ViolationRowLeadingCell>[],
    );
