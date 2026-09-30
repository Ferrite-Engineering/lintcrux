// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/widgets.dart';
import 'package:lintcrux/core/license/lintcrux_license_badge_strings.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// LintCrux-flavored wrapper around the cross-suite
/// `package:crux_license/crux_license.dart` [FeatureTierBadge].
///
/// Reads [L10N] from the current [BuildContext] and supplies a
/// [LintCruxLicenseBadgeStrings] adapter so the package widget renders
/// localized PRO / ENT labels and semantic phrases without each call site
/// having to construct the adapter itself. Visual behavior comes from the
/// package widget — `SizedBox.shrink` for `openCore` / `edu`, PRO chip in
/// `colorScheme.primary`, ENT chip in `colorScheme.tertiary`.
class LintCruxFeatureTierBadge extends StatelessWidget {
  /// Creates a tier badge labeling a feature that requires [requiredTier].
  const LintCruxFeatureTierBadge({
    required this.requiredTier,
    super.key,
  });

  /// The minimum tier required to use the feature this badge labels.
  final LicenseTier requiredTier;

  @override
  Widget build(BuildContext context) {
    return FeatureTierBadge(
      requiredTier: requiredTier,
      strings: LintCruxLicenseBadgeStrings(L10N.of(context)),
    );
  }
}
