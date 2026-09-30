// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Outcome classes for [VeribleFixService.checkAvailability].
///
/// Three buckets — installed-and-usable, installed-but-too-old, and
/// not-installed-at-all — let the UI surface a precise diagnostic
/// instead of conflating "missing" with "broken".
enum VeribleAvailabilityStatus {
  /// The configured / PATH-resolved Verible binary is present, the
  /// version was parsed successfully, and the build provides every
  /// capability LintCrux's `ProVeribleFixService` needs.
  available,

  /// A Verible binary is reachable but its reported version lacks one
  /// or more capabilities LintCrux requires (e.g. structured JSON
  /// output mode). The UI surfaces an "upgrade to version X" hint.
  installedButOldVersion,

  /// No Verible binary was found at the configured path or on PATH.
  /// The UI surfaces the installation link from `missingHint`.
  notInstalled,
}
