// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:lintcrux/core/app_info/about_providers.dart';
import 'package:lintcrux/core/platform/platform_localizations.dart';
import 'package:lintcrux/core/telemetry/lintcrux_telemetry_config.dart';
import 'package:lintcrux/core/telemetry/lintcrux_telemetry_storage.dart';
import 'package:lintcrux/core/telemetry/lintcrux_telemetry_strings.dart';
import 'package:lintcrux/core/telemetry/lintcrux_web_telemetry_storage.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/services/telemetry/telemetry_platform.dart';
import 'package:url_launcher/url_launcher.dart';

/// Root-scope overrides binding the cross-suite `crux_telemetry` package to
/// LintCrux's own configuration, persistence, build metadata, layout idiom,
/// locale, localized copy, and URL launcher.
///
/// Spread by `bootstrap` ahead of the Pro overlay's `proOverrides`
/// so the overlay can layer on top under the standard later-wins conflict
/// semantics — that is where the Enterprise `.crux-policy.json`
/// `telemetry: allow | deny` key will bind, as an override of
/// `telemetryConsentPromptVisibleProvider`.
///
/// Unlike WaveCrux, the localized string bundle **is** here rather than inside
/// `MaterialApp.builder`. LintCrux binds its other three string seams
/// (`crux_updates`, `crux_issue_reporter`, the About box) from the root scope
/// too — a nested `ProviderScope` inside the builder would re-parent the
/// container `WorkspaceRoot` derives every per-tab `ProviderContainer` from,
/// which is not a trade worth making for a string lookup. See
/// `core/platform/platform_localizations.dart` for the full argument. The
/// difference here is [l10nForSettingsTag] rather than `platformL10N()`: the
/// consent disclosure follows the in-app language switcher, because the one
/// screen where the app must not be in a different language from the rest of
/// the window is the one that says what leaves the user's machine.
final List<Override> lintcruxTelemetryOverrides = <Override>[
  // The one binding with no working default. A product that forgets it throws
  // at wiring rather than reporting somebody else's product slug on every
  // batch — and a wrong slug is rejected by the Worker with a 400 the client
  // never sees.
  cruxTelemetryConfigProvider.overrideWithValue(lintcruxTelemetryConfig),

  // The localized consent copy, resolved against the language the window is
  // actually drawn in.
  cruxTelemetryStringsProvider.overrideWith(
    (ref) => LintcruxTelemetryStrings(
      l10nForSettingsTag(ref.watch(appSettingsProvider).core.locale),
    ),
  ),

  // Where `telemetry.consent` and `telemetry.installationId` live. The package
  // default is an in-memory store, which would re-prompt the disclosure every
  // launch and re-mint the installation id every session — which is exactly
  // what the browser got until this became a choice, because the desktop
  // adapter's `dart:io` calls all fail there. See
  // [lintcruxTelemetryStorageFor].
  telemetryStorageProvider.overrideWithValue(
    lintcruxTelemetryStorageFor(web: kIsWeb),
  ),

  // "Learn more" on both consent surfaces. The package default throws rather
  // than silently doing nothing when the user taps a link on a privacy notice.
  telemetryUrlLauncherProvider.overrideWithValue(launchUrl),

  // The `app_version` envelope field. Until this resolves the package's
  // envelope resolver returns null and the flush skips — a version we do not
  // have must not be invented, because a bad `app_version` rejects the whole
  // batch at the Worker.
  telemetryAppVersionProvider.overrideWith(
    (ref) async => (await ref.watch(aboutBuildInfoProvider.future)).version,
  ),

  // The `form_factor` bucket. LintCrux ships one layout idiom plus the
  // read-only web viewer, so the derivation is `web` or `desktop` and there is
  // no device class to read — see `telemetryFormFactorFor`.
  //
  // The seam is `Provider<String?>` so a product whose idiom comes from the
  // widget tree can answer "not yet" and have the flush skip rather than report
  // a pre-layout default, the way a WaveCrux Pixel Tablet in portrait once
  // reported `desktop` on three of four launches. **LintCrux must not do
  // that.** `kIsWeb` is a compile-time constant and there is no second input:
  // the answer is known before anything is drawn, so deferring would cost a
  // flush interval to answer a question that was never open.
  telemetryFormFactorProvider.overrideWith(
    (ref) => telemetryFormFactorFor(isWeb: kIsWeb),
  ),

  // The display language actually in effect — the field that answers whether
  // the zh/zh_CN/ja/ko localizations earn their maintenance cost. The same
  // value the strings adapter above reads, so the envelope cannot report a
  // language the disclosure was not shown in.
  telemetryLocaleProvider.overrideWith(
    (ref) => ref.watch(appSettingsProvider).core.locale,
  ),
];

/// The telemetry store this build persists consent and the installation id
/// in: `SharedPreferences` in the browser, a JSON file on the desktop.
///
/// Desktop keeps the file because LintCrux has a second, Flutter-free
/// surface: `lintcrux --ci` cannot load a plugin, and the rule that the
/// headless runner transmits only on a stored affirmative consent is
/// worthless if it cannot read the consent the app wrote. A browser has no
/// headless surface and no `dart:io`, so it gets the preference store the
/// other three products use — see [LintcruxWebTelemetryStorage] for what the
/// file adapter did there.
///
/// [web] is `kIsWeb` in production, and a value rather than a constant read
/// so both branches are reachable from a test on either host.
TelemetryStorage lintcruxTelemetryStorageFor({required bool web}) => web
    ? const LintcruxWebTelemetryStorage()
    : const LintcruxTelemetryStorage();
