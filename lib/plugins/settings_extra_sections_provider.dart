// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Open-core extension point through which the Pro overlay
/// contributes additional categories to the Settings screen's rail.
///
/// Default returns an empty list so the open-core build's Settings screen
/// renders exactly the built-in categories it always has. The Pro overlay's
/// `proOverrides` replaces this provider with one that returns Custom Rules,
/// Trend Retention, Verible, and Lint Cache.
///
/// The entry type is the suite-shared [CruxSettingsExtraCategory]
/// (crux_settings_ui) — LintCrux's own `SettingsExtraSection` was the model
/// for it (stable id + context-taking builders), now with a *required* icon
/// and a plain `WidgetBuilder` body (bodies that need a `WidgetRef` return a
/// `Consumer`). All four suite apps share this seam shape.
///
/// Tier-gating note: the Settings screen rendering this provider does
/// **not** consult `licenseTierProvider` — Pro categories that need to
/// render an upsell card under `LicenseTier.openCore` are responsible for
/// that check inside their own body (matching the `CustomRulesSection`
/// pattern in the Pro overlay).
final settingsExtraSectionsProvider = Provider<List<CruxSettingsExtraCategory>>(
  (_) => const [],
);
