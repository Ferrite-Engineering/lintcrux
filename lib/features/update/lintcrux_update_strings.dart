// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/crux_updates.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// Adapter satisfying the `crux_updates` package's [CruxUpdateStrings]
/// interface from LintCrux's ARB-generated [L10N].
///
/// `crux-shared` packages carry no ARB files, so the update banner and the
/// manual "Check for Updates" action read their copy through this seam —
/// the same pattern [LicenseBadgeStrings] and `CruxAboutStrings` already
/// use. The product name lives inside the LintCrux ARB strings themselves
/// (`updateBannerMessage` reads "LintCrux {version} is available."), which
/// is why [bannerMessage] interpolates only the version.
class LintcruxUpdateStrings extends CruxUpdateStrings {
  /// Creates an adapter that reads localized update copy from [_l10n].
  const LintcruxUpdateStrings(this._l10n);

  final L10N _l10n;

  @override
  String bannerMessage(String version) => _l10n.updateBannerMessage(version);

  @override
  String get viewChangesAction => _l10n.updateViewChangesAction;

  @override
  String get updateNowAction => _l10n.updateNowAction;

  @override
  String get dismissLabel => _l10n.updateDismissLabel;

  @override
  String get checkInProgress => _l10n.updateCheckInProgress;

  @override
  String checkUpToDate(String version) => _l10n.updateCheckUpToDate(version);

  @override
  String get checkFailed => _l10n.updateCheckFailed;
}
