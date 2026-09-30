// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/plugins/pro_opener.dart';

/// Open-core extension point that, when invoked, opens the Pro
/// violation-bookmark management panel (the dockable list of every
/// bookmarked violation grouped by file path, with per-row "Jump",
/// "Edit Note", and "Remove" actions and a stale-bookmark filter).
///
/// The default is `null` (no opener registered), so the open-core build's
/// `LintcruxAction.openBookmarksManager` command activates without
/// throwing — the violation-bookmark feature is Pro.
///
/// The Pro overlay's `proOverrides` replaces this provider with one
/// that returns a callback mounting the panel. The signature mirrors
/// the other Pro opener providers.
final bookmarkPanelOpenerProvider = Provider<ProActionOpener?>(
  (_) => null,
);
