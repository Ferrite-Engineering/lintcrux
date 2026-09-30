// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/plugins/pro_opener.dart';

/// Open-core extension point that, when invoked, opens the Pro
/// filter-preset manager screen (the list of every preset with
/// edit / delete / duplicate row actions and a "+ New preset" affordance).
///
/// The default is `null` (no opener registered), so the open-core build's
/// `LintcruxAction.openFilterPresetManager` command activates without throwing
/// — user-authored filter-preset persistence is a Pro feature, so the null
/// default matches "feature not available in this tier" rather than a missing
/// implementation.
///
/// The Pro overlay's `proOverrides` replaces this provider with one
/// that returns a callback pushing the manager screen as a dialog or
/// route. The signature mirrors [waiverReviewOpenerProvider] so the
/// two openers feel the same to call sites.
final filterPresetManagerOpenerProvider = Provider<ProActionOpener?>(
  (_) => null,
);
