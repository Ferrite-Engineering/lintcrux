// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:lintcrux/core/theme/lintcrux_colors.dart';
import 'package:lintcrux/shared/widgets/lintcrux_icon_image.dart';

/// The LintCrux app icon with the suite's animated halo/pulse treatment
/// ([CruxGlowingAppIcon]), shimmering in the lint blue
/// ([LintcruxColors.brandSeed]) — each Crux app's welcome glow follows its
/// own brand color.
///
/// The animation itself (layer structure, breathing periods, light/dark
/// intensity) lives in `crux_workspace` so every Crux app's welcome screen
/// shares one implementation.
class GlowingAppIcon extends StatelessWidget {
  /// Creates a glowing LintCrux app icon.
  const GlowingAppIcon({super.key, this.size = 120});

  /// Pixel size of the icon itself. The widget reserves additional space
  /// around the icon for the halo and background glow.
  final double size;

  static final CruxGlowPalette _palette = CruxGlowPalette.fromSeed(
    LintcruxColors.brandSeed,
  );

  @override
  Widget build(BuildContext context) {
    return CruxGlowingAppIcon(
      icon: LintcruxIconImage(size: size),
      palette: _palette,
      size: size,
    );
  }
}
