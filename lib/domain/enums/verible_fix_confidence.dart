// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Confidence band for a Verible-proposed auto-fix.
///
/// Verible's own diagnostic stream classifies its fixes by how
/// mechanical they are: a missing semicolon insertion is high
/// confidence; a spacing reformat is medium; a structural refactor
/// is low. The `FixReviewDialog` surfaces filter chips per band so
/// users can apply high-confidence fixes in bulk without auditing
/// every line.
enum VeribleFixConfidence {
  /// Mechanical, near-unambiguous fix (e.g. missing semicolon,
  /// trailing whitespace). Safe to apply without per-line review.
  high,

  /// Slightly judgmental fix (formatting / style nuance). Worth a
  /// quick eyeball but typically safe.
  medium,

  /// Judgment-call fix (structural refactor, naming change). Should
  /// be reviewed line-by-line.
  low,
}
