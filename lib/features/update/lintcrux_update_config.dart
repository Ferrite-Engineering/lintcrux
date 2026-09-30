// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/crux_updates.dart';
import 'package:lintcrux/core/help_urls.dart';

/// LintCrux's [CruxUpdateConfig] — the one piece of per-product
/// configuration the cross-suite update mechanism needs.
///
/// Spread into the root `ProviderScope` from `bootstrap()` as
/// `cruxUpdateConfigProvider.overrideWithValue(lintcruxUpdateConfig)`.
/// Without that override the package default throws at first read, which
/// is deliberate: a product that forgets to wire its manifest fails at app
/// wiring rather than silently never checking for updates.
///
/// No `appStoreUri` / `playStoreUri` and no `checkOnMobile`: LintCrux ships
/// on Linux / macOS / Windows plus a read-only web viewer, and has no
/// iOS/Android target (see CLAUDE.md "Platform Targets"). On web the update
/// *check* still runs — its manifest response carries the `server_time`
/// watermark that hardens beta expiry — while `UpdateBanner` renders
/// nothing, because a web build self-updates on deploy.
final CruxUpdateConfig lintcruxUpdateConfig = CruxUpdateConfig(
  productName: 'LintCrux',
  manifestUri: HelpUrls.updateManifest,
  downloadPageUri: HelpUrls.download,
);
