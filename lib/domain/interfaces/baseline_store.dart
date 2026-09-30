// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/models/lint_baseline.dart';

/// Persistence interface for the per-project active [LintBaseline].
///
/// Open Core ships a no-op implementation (`NoopBaselineStore`) — the
/// baseline & delta workflow is a Pro feature.
/// The Pro overlay supplies `JsonFileBaselineStore` that
/// reads/writes a `<project-root>/.lintcrux-baseline.json` file with
/// schema-version-tagged content. The Enterprise overlay is
/// expected to layer a shared / cloud-hosted store with cross-team
/// baseline sharing on the same interface.
///
/// Every reader is Pro overlay code (the status chip, the comparison screen,
/// the snapshot the overlay publishes into `currentBaselineSnapshotProvider`
/// for the table's view-mode filter); the open core declares the seam and
/// reads it nowhere. The headless `--fail-on-new-violations` gate reads the
/// same file through `CliBaselineReader`, not through this interface.
///
/// A project has **at most one** active baseline. Replacing it is
/// allowed (the "rebase" workflow) — implementations
/// must atomically swap the active baseline and record both the old
/// and new ids to the [BaselineAuditSink] so the history is
/// reconstructible from the audit trail.
abstract class BaselineStore {
  /// Returns the currently active baseline, or `null` if no baseline
  /// has been set for this project.
  Future<LintBaseline?> activeBaseline();

  /// Atomically sets [baseline] as the new active baseline, replacing
  /// any previous active baseline. Implementations record both the
  /// previous baselineId (when present) and the new one to the
  /// configured [BaselineAuditSink].
  ///
  /// Throws [UnsupportedError] on the open-core noop implementation
  /// because the baseline feature is Pro-tier.
  Future<void> setBaseline(LintBaseline baseline);

  /// Clears the active baseline. After this call, [activeBaseline]
  /// returns `null` until a new baseline is set. Implementations
  /// record the cleared baselineId to the audit sink.
  Future<void> clearBaseline();

  /// Stream that emits the new active baseline (or `null` after a
  /// clear) on every mutation. Used by the status chip and the
  /// violation table view-mode toggle to refresh without polling.
  Stream<LintBaseline?> watch();
}
