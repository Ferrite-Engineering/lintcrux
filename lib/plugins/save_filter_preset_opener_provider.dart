// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/plugins/pro_opener.dart';

/// Open-core extension point that, when invoked, opens the Pro
/// "Save current filter as preset…" dialog pre-populated with the
/// active table state.
///
/// The default is `null` (no opener registered), so the open-core build's
/// `LintcruxAction.savePresetFromCurrentFilter` command activates
/// without throwing — user-authored filter-preset persistence is Pro.
///
/// The Pro overlay's `proOverrides` replaces this provider with one
/// that returns a callback mounting the save dialog. The signature
/// mirrors [filterPresetManagerOpenerProvider].
final saveFilterPresetOpenerProvider = Provider<ProActionOpener?>(
  (_) => null,
);
