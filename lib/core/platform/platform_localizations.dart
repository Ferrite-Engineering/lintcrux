// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart'
    show Locale, WidgetsApp, basicLocaleListResolution;
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// Resolves [L10N] for the platform's preferred locale, without a
/// [BuildContext].
///
/// Needed by the root-scope overrides of the `crux_updates` and
/// `crux_issue_reporter` string seams: both packages read their copy from a
/// plain `Provider`, and a `Provider` body has no context to call `L10N.of`
/// on. The alternative — a nested `ProviderScope` inside
/// `MaterialApp.builder` — would re-parent the container that `WorkspaceRoot`
/// derives every per-tab `ProviderContainer` from, which is not a trade worth
/// making for a string lookup.
///
/// Uses the same resolution [WidgetsApp] itself applies, over the same
/// [L10N.supportedLocales], so the strings these seams return match the rest
/// of the UI. LintCrux does not pass an explicit `locale:` to its
/// `MaterialApp`, so the platform locale *is* the effective locale; if a
/// runtime locale switcher ever lands, this becomes the thing that has to
/// follow it.
L10N platformL10N() {
  final locale = basicLocaleListResolution(
    PlatformDispatcher.instance.locales,
    L10N.supportedLocales,
  );
  return lookupL10N(locale);
}

/// The [Locale] a persisted Settings → Appearance language tag selects.
///
/// LintCrux stores the preference as `CoreSettings.locale` (`en`, `zh_CN`,
/// `ja`, `ko`) and hands the resolved [Locale] to `MaterialApp.locale`, so this
/// mapping — not [platformL10N] — is what decides the language the user
/// actually sees. Extracted so the two places that need it (the `MaterialApp`
/// and the telemetry consent surfaces, which render their own copy from a
/// root-scope provider) cannot disagree about which language is in effect.
///
/// Anything unrecognised falls back to English, which is also the codec's
/// default, so an unreadable or future preference degrades to the one locale
/// that always exists.
Locale localeForSettingsTag(String tag) => switch (tag) {
  'zh_CN' => const Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
  'ja' => const Locale('ja'),
  'ko' => const Locale('ko'),
  _ => const Locale('en'),
};

/// [L10N] for the persisted Settings → Appearance language [tag].
///
/// The context-free counterpart of `L10N.of(context)` for a root-scope
/// provider. Unlike [platformL10N] it follows the in-app language switcher,
/// which is what a privacy disclosure has to do: showing it in the OS language
/// while the rest of the window is in the user's chosen one would be the one
/// screen in the app where that mismatch matters.
L10N l10nForSettingsTag(String tag) => lookupL10N(localeForSettingsTag(tag));
