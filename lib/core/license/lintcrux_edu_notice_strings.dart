// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// LintCrux's localized [CruxEduNoticeStrings] for the status-bar statement
/// that an educational licence is for non-commercial use.
///
/// The tooltip is four whole sentences in the ARB files rather than one
/// sentence assembled from fragments, so each locale words and punctuates the
/// email and end-date variants its own way.
///
/// [exportMark] stays English in every locale: the HTML report it closes is
/// English throughout, and the command line writes the same line.
class LintCruxEduNoticeStrings extends CruxEduNoticeStrings {
  /// Wraps the localizations for the nearest context.
  const LintCruxEduNoticeStrings(this._l10n);

  final L10N _l10n;

  @override
  String get statusLabel => _l10n.eduStatusLabel;

  @override
  String statusTooltip({String? email, String? validUntil}) =>
      switch ((email, validUntil)) {
        (final String email, final String until) =>
          _l10n.eduStatusTooltipForEmailValidUntil(email, until),
        (final String email, null) => _l10n.eduStatusTooltipForEmail(email),
        (null, final String until) => _l10n.eduStatusTooltipValidUntil(until),
        (null, null) => _l10n.eduStatusTooltip,
      };

  @override
  String exportMark(String productName) =>
      const CruxEduNoticeStringsEn().exportMark(productName);
}
