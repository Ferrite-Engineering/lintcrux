// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Sizing constants shared by the beta-expiry banner and blocking modal.
///
/// LintCrux is desktop-first with a desktop-class web viewer and has no
/// phone/tablet target, so there is no `MobileMetrics`-style device-class
/// lookup to read these from (see CLAUDE.md "Platform Targets"). Fixed
/// constants keep both widgets honest about the one form factor that ships,
/// while still naming the accessibility floor explicitly.
abstract final class BetaExpiryMetrics {
  /// Minimum hit-area edge (dp) for every interactive affordance in the
  /// beta-expiry surfaces. The suite-wide accessibility floor is 44 dp; never
  /// lower this.
  static const double touchTarget = 44;

  /// Icon edge (dp) for the banner's leading glyph and dismiss button.
  static const double iconSize = 20;

  /// Font size for the banner message and the modal body copy.
  static const double bodyText = 13;
}
