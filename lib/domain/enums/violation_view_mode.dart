// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// View mode for the violation table — controls which slice of the
/// classified-against-baseline result is rendered.
///
/// The table watches [ViolationViewMode] (open-core
/// `violationViewModeProvider`) and applies a post-filter when the
/// mode is anything other than [allViolations]. Two of the three
/// modes require an active baseline to be meaningful; when no
/// baseline exists, the open-core post-filter degrades them to
/// [allViolations] semantics (the toggle UI is responsible for
/// disabling the modes that require a baseline — see the Pro
/// `BaselineViewModeToggle`).
enum ViolationViewMode {
  /// Render every violation (no baseline filtering). Default.
  allViolations,

  /// Render only violations introduced after the active baseline
  /// (the `newViolations` slice of [BaselineDelta]). Requires an
  /// active baseline.
  onlyNew,

  /// Render only baseline entries that no longer fire in the current
  /// run (the `resolvedViolations` slice of [BaselineDelta]).
  /// Requires an active baseline.
  onlyResolved,
}
