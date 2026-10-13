// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/features/bookmarks/screens/bookmark_panel.dart';
import 'package:lintcrux/features/bookmarks/services/bookmark_dialog_launcher.dart';
import 'package:lintcrux/plugins/pro_opener.dart';

/// Opens the bookmark management panel ([BookmarkPanel]).
///
/// Reached from `LintcruxAction.openBookmarksManager` (menu bar, command
/// palette) and from the bookmark count badge above the violation table.
/// A provider rather than a direct call so tests can observe the dispatch.
final Provider<ProActionOpener?> bookmarkPanelOpenerProvider =
    Provider<ProActionOpener?>((_) => BookmarkPanel.showAsDialog);

/// Toggles the bookmark of the active tab's selected violation: opens the
/// bookmark dialog in create or edit mode as appropriate.
///
/// Reached from `LintcruxAction.toggleBookmarkForCurrentViolation`.
final Provider<ProActionOpener?> toggleBookmarkOpenerProvider =
    Provider<ProActionOpener?>((_) => toggleBookmarkForSelectedViolation);
