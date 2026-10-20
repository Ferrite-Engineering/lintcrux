// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/bookmarks/widgets/bookmark_dialog.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/features/workspace/services/active_tab_scope.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/bookmarks/violation_bookmark_lookup_provider.dart';
import 'package:lintcrux/services/bookmarks/violation_bookmark_store_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';

/// Opens [BookmarkDialog] for [violation]: in edit mode when it is already
/// bookmarked, in create mode otherwise.
///
/// [container] is the tab's `ProviderContainer`, read here for the existing
/// bookmark. The dialog itself reads and writes the tab's own bookmark store,
/// so it is shown on that tab's navigator ([ActiveTab.navigatorFor]: every
/// caller is either inside the tab or acting on the active tab) and built
/// under the tab's one scope.
///
/// The column icon, the Toggle Bookmark action and the bookmark panel's
/// Edit entry all reach this dialog, so they share one `ModalGuard` key per
/// tab: a fast double-fire from any of them must not stack two dialogs over
/// the same violation.
Future<void> showBookmarkDialogFor(
  BuildContext context,
  ProviderContainer container,
  Violation violation,
) async {
  final store = container.read(violationBookmarkStoreProvider);
  final fingerprint = computeBookmarkFingerprint(
    violation,
    projectRoot: container.read(currentProjectProvider)?.rootPath ?? '',
  );
  final existing = await store.lookupByFingerprint(fingerprint);
  if (!context.mounted) return;
  await ModalGuard.run(ActiveTab.guardKey(context, 'bookmarkDialog'), () async {
    await showCruxDialog<void>(
      context: context,
      // A note + color-tag editor holding in-progress user input: closing
      // must be a deliberate act, never a stray scrim click.
      barrierDismissible: false,
      navigator: ActiveTab.navigatorFor(context),
      builder: (_) => BookmarkDialog(existing: existing, violation: violation),
    );
  });
}

/// The Toggle Bookmark action: opens [showBookmarkDialogFor] for the
/// active tab's selected violation, or says that a violation must be
/// selected first.
Future<void> toggleBookmarkForSelectedViolation(BuildContext context) async {
  final container =
      activeTabContainerOf(context) ??
      ProviderScope.containerOf(context, listen: false);
  final selected = container.read(selectedViolationProvider);
  if (selected == null) {
    showCruxInfoSnack(context, L10N.of(context).bookmarkNoSelectionSnackbar);
    return;
  }
  await showBookmarkDialogFor(context, container, selected);
}
