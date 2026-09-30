// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/core/cli/cli_exit_codes.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/engine_run_status.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:meta/meta.dart';

/// Everything a headless run produced, plus the exit code it maps to.
///
/// Separating "what happened" from "what we printed and returned" is
/// what makes the exit-code contract testable without spawning a
/// process: `HeadlessRunner` returns one of these, `bin/lintcrux.dart`
/// prints it and calls `exit(result.exitCode)`, and the unit tests
/// assert on the same object the binary acts on.
@immutable
class HeadlessRunResult {
  /// Creates a [HeadlessRunResult].
  const HeadlessRunResult({
    required this.exitCode,
    this.violations = const <Violation>[],
    this.newViolations = const <Violation>[],
    this.persistingViolations = const <Violation>[],
    this.resolvedViolationCount = 0,
    this.suppressedCount = 0,
    this.statuses = const <String, EngineRunStatus>{},
    this.problems = const <String>[],
    this.diagnostics = const <String>[],
    this.baselinePath,
    this.baselineApplied = false,
    this.exportPath,
    this.projectName,
  });

  /// A failure that never got as far as running engines.
  const HeadlessRunResult.failed({
    required int code,
    required List<String> problems,
    List<String> diagnostics = const <String>[],
  }) : this(exitCode: code, problems: problems, diagnostics: diagnostics);

  /// The process exit code. One of [CliExitCode.all].
  final int exitCode;

  /// Every violation that survived the transformer chain, suppressed
  /// ones included. [reportableViolations] is the subset the gates act
  /// on.
  final List<Violation> violations;

  /// Violations absent from the baseline. Empty when no baseline was
  /// consulted (see [baselineApplied]).
  final List<Violation> newViolations;

  /// Violations present in the baseline. Empty when no baseline was
  /// consulted.
  final List<Violation> persistingViolations;

  /// How many baseline entries no longer appear in this run — findings
  /// the change set fixed. Reported for encouragement, never gated on.
  final int resolvedViolationCount;

  /// How many violations a waiver or source pragma suppressed. These are
  /// excluded from [reportableViolations] and therefore from the gates.
  final int suppressedCount;

  /// Terminal per-engine status keyed by engine id.
  final Map<String, EngineRunStatus> statuses;

  /// Fatal, human-readable problems. Non-empty implies a non-zero
  /// [exitCode]; printed to stderr.
  final List<String> problems;

  /// Non-fatal notes worth printing — a skipped engine, an absent
  /// baseline, an engine that received no compatible source files.
  final List<String> diagnostics;

  /// The baseline file that was consulted, or `null` when the gate was
  /// not requested.
  final String? baselinePath;

  /// Whether a baseline was actually loaded. `false` with a non-null
  /// [baselinePath] means "asked for, not found" — every violation is
  /// then classified as new, which is the strict reading.
  final bool baselineApplied;

  /// Where the `--export` artifact was written, or `null`.
  final String? exportPath;

  /// The project's name, for the summary line.
  final String? projectName;

  /// Violations the gates act on: everything not suppressed by a waiver
  /// or a source pragma.
  List<Violation> get reportableViolations => <Violation>[
    for (final v in violations)
      if (!v.isSuppressed) v,
  ];

  /// Count of reportable violations per severity, highest first.
  Map<Severity, int> get severityCounts {
    final out = <Severity, int>{};
    for (final v in reportableViolations) {
      out[v.severity] = (out[v.severity] ?? 0) + 1;
    }
    return out;
  }

  /// Engine ids whose terminal phase was a failure the gate cares about.
  List<String> get failedEngineIds => <String>[
    for (final entry in statuses.entries)
      if (entry.value.phase == EngineRunPhase.failed ||
          entry.value.phase == EngineRunPhase.unavailable)
        entry.key,
  ];

  /// The stable label for [exitCode], printed on the summary line.
  String get exitLabel => CliExitCode.labelFor(exitCode);
}
