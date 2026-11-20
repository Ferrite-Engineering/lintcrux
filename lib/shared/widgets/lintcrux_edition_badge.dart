// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/core/license/lintcrux_license_badge_strings.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// LintCrux-flavored wrapper around the cross-suite
/// `package:crux_license/crux_license.dart` [EditionBadge].
///
/// Reads [L10N] from the current [BuildContext] and supplies a
/// [LintCruxLicenseBadgeStrings] adapter so the package widget renders the
/// localized chip without each call site constructing the adapter itself.
///
/// States the edition in force — EDU, PRO or ENT — and renders nothing at
/// open core. It takes no tier: the package widget reads
/// `licenseTierProvider` itself, because a statement about what the user owns
/// has exactly one correct source. Rendering nothing at open core is what makes
/// it safe to mount unconditionally in the status bar's trailing slot.
///
/// Under an educational licence it renders nothing too: the bar's
/// `LintcruxEduStatusChip` carries the EDU chip itself, with the
/// non-commercial terms beside it, and two EDU chips side by side would say
/// the same thing twice.
class LintCruxEditionBadge extends ConsumerWidget {
  /// Creates an edition badge for the licence currently in force.
  const LintCruxEditionBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (cruxIsEduLicense(ref.watch(licenseStatusProvider))) {
      return const SizedBox.shrink();
    }
    return EditionBadge(
      strings: LintCruxLicenseBadgeStrings(L10N.of(context)),
    );
  }
}
