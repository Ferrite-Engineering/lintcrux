// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/plugins/pro_opener.dart';

/// Open-core extension point that, when invoked, opens the Pro
/// baseline-vs-current comparison screen (sections: New / Persisting /
/// Resolved, each filterable, each with a copy / export action).
///
/// The default is `null` (no opener registered), so the open-core build's
/// `LintcruxAction.openBaselineComparison` command activates without throwing —
/// the baseline & delta workflow is a Pro feature, so the null default matches
/// "feature not available in this tier" rather than a missing implementation.
///
/// The Pro overlay's `proOverrides` replaces this provider with one
/// that returns a callback pushing the comparison screen as a dialog
/// or route. The signature mirrors [waiverReviewOpenerProvider] so the
/// two openers feel the same to call sites — the activating
/// `BuildContext` is the only argument.
final baselineComparisonOpenerProvider = Provider<ProActionOpener?>(
  (_) => null,
);
