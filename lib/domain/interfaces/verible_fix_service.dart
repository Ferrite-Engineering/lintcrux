// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/verible_availability_status.dart';
import 'package:lintcrux/domain/models/verible_availability.dart';
import 'package:lintcrux/domain/models/verible_fix_apply_result.dart';
import 'package:lintcrux/domain/models/verible_fix_batch.dart';

/// Persistence + execution surface for Google Verible's auto-fix
/// integration.
///
/// Open Core ships [NoopVeribleFixService] — `checkAvailability`
/// returns `notInstalled`; `dryRun` and `apply` are silent no-ops.
/// The Pro overlay supplies `ProVeribleFixService` which shells out
/// to the installed `verible-verilog-lint` / `verible-verilog-format`
/// binaries.
abstract class VeribleFixService {
  /// Probes the configured / PATH-resolved Verible binary and
  /// reports its status, version, and capabilities. The
  /// `veribleAvailabilityProvider` caches the result for the session
  /// and invalidates on settings change.
  Future<VeribleAvailability> checkAvailability();

  /// Runs Verible in dry-run mode against the active project (or a
  /// subset specified by [scopeFilter] / [specificRules]) and
  /// returns the proposed fixes as a [VeribleFixBatch] with
  /// `dryRunOnly == true`.
  ///
  /// `scopeFilter` (when non-null) restricts the dry-run to a
  /// specific subtree or file. `specificRules` (when non-empty)
  /// restricts the dry-run to a specific rule set — used by the
  /// per-violation "Suggest fix" surface to scope the proposal
  /// search to the offending rule + file.
  ///
  /// Returns an empty batch when nothing needs fixing or when the
  /// Pro service is unavailable.
  Future<VeribleFixBatch> dryRun({
    String? scopeFilter,
    List<String>? specificRules,
  });

  /// Applies the selected subset of [batch.proposals] (identified by
  /// [selectedProposalIds]) to the corresponding files. Returns one
  /// [VeribleFixApplyResult] per selected proposal.
  ///
  /// Atomicity: when multiple selected proposals target the same
  /// file, the implementation must combine them into one atomic
  /// write. When selected proposals overlap line ranges within the
  /// same file, the implementation must apply only the higher-
  /// confidence fix and emit a `conflictedWithOtherFix` result for
  /// the lower-confidence proposal.
  Future<List<VeribleFixApplyResult>> apply(
    VeribleFixBatch batch,
    List<String> selectedProposalIds,
  );
}

/// Open-core default. `checkAvailability` reports `notInstalled` so
/// the UI surfaces the installation hint; `dryRun` returns an empty
/// batch; `apply` returns an empty result list.
class NoopVeribleFixService implements VeribleFixService {
  /// Creates a [NoopVeribleFixService].
  const NoopVeribleFixService();

  @override
  Future<VeribleAvailability> checkAvailability() async {
    return const VeribleAvailability(
      status: VeribleAvailabilityStatus.notInstalled,
      missingHint:
          'Install Verible from https://github.com/chipsalliance/verible '
          'to enable auto-fix integration.',
    );
  }

  @override
  Future<VeribleFixBatch> dryRun({
    String? scopeFilter,
    List<String>? specificRules,
  }) async {
    return VeribleFixBatch(
      batchId: 'noop',
      generatedAt: DateTime.now().toUtc(),
      proposals: const [],
      sourceProject: '',
    );
  }

  @override
  Future<List<VeribleFixApplyResult>> apply(
    VeribleFixBatch batch,
    List<String> selectedProposalIds,
  ) async {
    return const <VeribleFixApplyResult>[];
  }
}
