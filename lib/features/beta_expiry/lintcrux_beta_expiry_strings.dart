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
