// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_license/crux_license.dart';
import 'package:crux_status_bar/crux_status_bar.dart';
import 'package:flutter/material.dart';
import 'package:lintcrux/core/license/lintcrux_edu_notice_strings.dart';
import 'package:lintcrux/core/license/lintcrux_license_badge_strings.dart';
import 'package:lintcrux/features/settings/screens/settings_screen.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// The status bar's statement that this copy runs on an educational licence:
/// the shared [CruxEduStatusChip] in LintCrux's words and the bar's type.
///
/// Renders nothing unless `licenseStatusProvider` resolves to the
/// Educational tier, so every bar mounts it unconditionally, last in the
/// trailing slot (LintCrux's bar has no panel chevron to sit before). The
/// provider is read from the scope the bar is mounted in: the root scope for
/// the workspace bar and the imported-report window alike, which is the
/// scope the Pro overlay overrides with its licence service. Per-tab
/// containers are parented to that root and do not override it.
///
/// A click opens Settings at the License category, the destination of the
/// licence-expiry strip's action.
class LintcruxEduStatusChip extends StatelessWidget {
  /// Creates the chip.
  const LintcruxEduStatusChip({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return CruxEduStatusChip(
      strings: LintCruxEduNoticeStrings(l10n),
      badgeStrings: LintCruxLicenseBadgeStrings(l10n),
      textStyle: CruxStatusBar.resolveTextStyle(context),
      onTap: () => unawaited(
        SettingsScreen.openAdaptive(
          context,
          initialCategoryId: kCruxLicenseCategoryId,
        ),
      ),
    );
  }
}
