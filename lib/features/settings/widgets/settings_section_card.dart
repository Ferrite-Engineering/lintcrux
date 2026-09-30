// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';

/// A LintCrux settings-section body wrapped in the suite-shared grouped card
/// ([CruxSettingsCard]) with uniform interior padding.
///
/// Each LintCrux settings section is a self-scrolling `ListView` (the dual-pane
/// shell runs with `scrollableDetail: false`), so the card sits *inside* the
/// section's scrollable rather than the shell wrapping it. This gives the
/// card-based look used across the suite (WaveCrux / NetCrux / SimCrux) while
/// keeping each section's own scroll + sub-headings.
class SettingsSectionCard extends StatelessWidget {
  /// Creates a section card around [children].
  const SettingsSectionCard({required this.children, super.key});

  /// The section's content, laid out in a stretched column inside the card.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return CruxSettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}
