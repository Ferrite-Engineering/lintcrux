// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/core/help_urls.dart';
import 'package:lintcrux/features/settings/widgets/settings_section_card.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// Settings → CXP Cross-Probe page.
///
/// The suite-shared [CruxCxpSettingsSection] (crux_cxp_ui): the four CXP
/// settings, each saved at once, and the status line. A change takes effect
/// at once: switching the server off stops it, a new port restarts it on that
/// port, and the other two are read at the next request or selection.
///
/// LintCrux adds the link to the cross-probe documentation as its own row.
class SettingsRemoteControlSection extends ConsumerWidget {
  /// Creates a [SettingsRemoteControlSection].
  const SettingsRemoteControlSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        SettingsSectionCard(
          children: [
            const CruxCxpSettingsSection(),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: CruxHelpLink(
                url: HelpUrls.crossProbe,
                tooltip: l10n.helpLinkLearnMore,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
