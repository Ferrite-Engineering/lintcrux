// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/plugins/pro_opener.dart';

/// Open-core extension point that, when invoked, opens the managed-
/// waiver review surface (the table of every waiver for the active
/// project with edit / delete row actions).
///
/// The default is `null` (no opener registered), so the open-core build's
/// `LintcruxAction.openWaiverReview` command activates without
/// throwing — the managed waiver system is a Pro feature, so the
/// null default matches "feature not available in this tier"
/// rather than a missing implementation.
///
/// The Pro overlay's `proOverrides` replaces this provider with one
/// that returns a callback pushing the `WaiverReviewScreen` as a
/// dialog or route. The signature exposes the activating
/// `BuildContext` so the opener can mount a dialog rooted at the
/// user's current screen without each call site rebuilding the route
/// argument.
final waiverReviewOpenerProvider = Provider<ProActionOpener?>(
  (_) => null,
);
