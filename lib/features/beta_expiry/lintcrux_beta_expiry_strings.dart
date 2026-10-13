// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// Binds `crux_license`'s [CruxBetaExpiryStrings] to LintCrux's ARB.
///
/// The banner widget was hand-copied into all four products before
/// `CruxBetaExpiryBanner` lifted it into `crux_license`. The ARB keys are
/// unchanged — this is a re-binding, not a translation job.
class LintcruxBetaExpiryStrings extends CruxBetaExpiryStrings {
  /// Wraps a resolved [L10N].
  const LintcruxBetaExpiryStrings(this._l10n);

  final L10N _l10n;

  @override
  String bannerMessage(int days) => _l10n.betaExpiryBannerMessage(days);

  @override
  String get bannerAction => _l10n.betaExpiryBannerAction;

  @override
  String get dismissLabel => _l10n.betaExpiryDismissLabel;
}

/// Binds `crux_license`'s [CruxBetaExpiredStrings] to LintCrux's ARB.
///
/// The blocking modal followed the banner into `crux_license` as
/// `CruxBetaExpiredOverlay`, which also took the app behind it out of focus
/// and semantics. The four ARB keys are the ones LintCrux's own copy of the
/// modal used, so this is a re-binding, not a translation job.
class LintcruxBetaExpiredStrings extends CruxBetaExpiredStrings {
  /// Wraps a resolved [L10N].
  const LintcruxBetaExpiredStrings(this._l10n);

  final L10N _l10n;

  @override
  String get title => _l10n.betaExpiryExpiredTitle;

  @override
  String get body => _l10n.betaExpiryExpiredBody;

  @override
  String get downloadLabel => _l10n.betaExpiryExpiredAction;

  @override
  String get quitLabel => _l10n.betaExpiryExpiredQuit;
}
