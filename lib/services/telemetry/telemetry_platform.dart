// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart' show kTelemetryFormFactors;

/// Maps the layout idiom the app **already** uses onto the coarse
/// `form_factor` bucket (`crux_telemetry`'s [kTelemetryFormFactors]).
///
/// This is the one half of the telemetry envelope that stays in LintCrux, and
/// deliberately: the derivation reads the idiom the app actually drew rather
/// than a new breakpoint set, so telemetry can never disagree with what the
/// user is looking at. A second breakpoint set inside the shared package is
/// exactly how the two would come to disagree.
///
/// LintCrux's idiom is a **single** one. The product is desktop-first with a
/// desktop-class read-only web viewer and has no phone or tablet target: the
/// `panes` `IdeLayout` is the only layout, with no `AdaptiveScaffold`, no
/// phone fallback and no tablet collapsing. That is why
/// this function takes `isWeb` and nothing else: there is no `DeviceClass`
/// equivalent to read because LintCrux never made that distinction, and
/// inventing one here purely to feed telemetry would be exactly the
/// disagreement the rule exists to prevent. A narrow LintCrux window is a
/// narrow desktop window, and it reports `desktop`.
///
/// `kIsWeb` wins outright: a browser tab is a browser tab whatever its width,
/// and `web` vs `desktop` is the split the roadmap question ("does the
/// read-only web viewer earn its maintenance") actually needs. No dimensions
/// are sent, and none are derivable from the two buckets LintCrux can report.
String telemetryFormFactorFor({required bool isWeb}) =>
    isWeb ? 'web' : 'desktop';
