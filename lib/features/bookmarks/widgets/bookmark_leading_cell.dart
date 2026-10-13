// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/features/bookmarks/widgets/bookmark_column_icon.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/plugins/violation_row_leading_cells_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';

/// The bookmark column: the leftmost column of the violation table.
///
/// Width: 32 dp, matching the selection check box beside it.
///
/// The header slot renders only a tooltip-anchored bookmark icon (no
/// label) so the table header stays compact; the column's purpose is
/// communicated by the icon itself plus the visible row icons.
final ViolationRowLeadingCell kBookmarkLeadingCell = ViolationRowLeadingCell(
  id: 'bookmark',
  width: 32,
  bodyBuilder: (_, _, violation) => BookmarkColumnIcon(violation: violation),
  headerBuilder: (context, _) {
    final l10n = L10N.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: l10n.bookmarkColumnHeaderTooltip,
      child: Center(
        child: Icon(
          Icons.bookmark_outline,
          size: 16,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  },
);

/// Whether the table under [ref] can hold bookmarks: a project is open, so
/// there is a project directory for the bookmark file. The imported-report
/// and web viewers have none, and show no bookmark column or count badge.
bool watchBookmarksAvailable(WidgetRef ref) => ref.watch(
  currentProjectProvider.select((p) => (p?.rootPath ?? '').isNotEmpty),
);

/// The leading cells of the violation table: the bookmark column when
/// [watchBookmarksAvailable], then every overlay contribution from
/// [violationRowLeadingCellsProvider].
List<ViolationRowLeadingCell> watchViolationLeadingCells(WidgetRef ref) => [
  if (watchBookmarksAvailable(ref)) kBookmarkLeadingCell,
  ...ref.watch(violationRowLeadingCellsProvider),
];
