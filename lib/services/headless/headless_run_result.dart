// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/core/cli/cli_exit_codes.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/engine_run_outcome.dart';
import 'package:lintcrux/domain/models/engine_run_status.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:meta/meta.dart';

/// What a [HeadlessFailure] is about: the command line, an input, an engine,
/// or the export the run was asked to write.
enum HeadlessFailureKind {
  /// The command line names nothing usable (exit 64).
  usage,

  /// An input exists and cannot be used: the project, the `--config`
  /// overlay, the baseline, a filelist or EDAM import.
  input,

  /// An engine failed, timed out, was missing or cancelled, or could not
  /// analyse the design.
  engine,

  /// The `--export` file could not be written.
  output,
}

/// One of [HeadlessRunResult.problems], with what it is about and a stable
/// code, so the `--json` document can say which outcome it is without
/// reading the English.
@immutable
class HeadlessFailure {
  /// A failure of [kind] with the stable [code] and the [message] printed
  /// on stderr.
  const HeadlessFailure(this.kind, this.code, this.message);

  /// What it is about.
  final HeadlessFailureKind kind;

  /// Stable, lower-case, dot-separated (`engine.timeout`).
  final String code;

  /// The problem, exactly as [HeadlessRunResult.problems] holds it.
  final String message;

  @override
  bool operator ==(Object other) =>
      other is HeadlessFailure &&
      other.kind == kind &&
      other.code == code &&
      other.message == message;

  @override
  int get hashCode => Object.hash(kind, code, message);

  @override
  String toString() => 'HeadlessFailure($code: $message)';
}

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
    this.gateRequested = false,
    this.failures = const <HeadlessFailure>[],
    this.engineOutcomes = const <String, EngineRunOutcome>{},
    this.project,
    this.projectFilePath,
  });

  /// A failure that never got as far as running engines.
  const HeadlessRunResult.failed({
    required int code,
    required List<String> problems,
    List<String> diagnostics = const <String>[],
    List<HeadlessFailure> failures = const <HeadlessFailure>[],
    LintProject? project,
    String? projectFilePath,
  }) : this(
         exitCode: code,
         problems: problems,
         diagnostics: diagnostics,
         failures: failures,
         project: project,
         projectFilePath: projectFilePath,
       );

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

  /// Whether any gate applied to this run: `--exit-code`,
  /// `--fail-on-new-violations`, or an organization's violation ceiling.
  /// Decides how a run that exits `0` with findings is labelled.
  final bool gateRequested;

  /// [problems] with what each is about, in the same order, when the code
  /// that made this result classified them; empty otherwise.
  final List<HeadlessFailure> failures;

  /// How each engine's run ended, by engine id, as `ParallelEngineRunner`
  /// reported it: the one place a watchdog kill is told apart from a crash,
  /// both of which are [EngineRunPhase.failed]. A cancelled engine has none.
  final Map<String, EngineRunOutcome> engineOutcomes;

  /// The project as it was linted (after `--config`, `--constraints` and
  /// `--param`), or `null` when none was resolved.
  final LintProject? project;

  /// The `.lintcrux` file the project came from, absolute, or `null` for
  /// loose source files.
  final String? projectFilePath;

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

  /// The label for [exitCode], printed on the summary line.
  ///
  /// [CliExitCode.labelFor], except for a run that exits `0` with findings,
  /// where `clean` beside `1 error` reads as a contradiction. With no gate
  /// that run is a report, labelled [noGateRequestedLabel]. With a gate it
  /// passed: every finding was in the baseline, or the count stayed under
  /// the organization's ceiling. It is labelled [gatePassedLabel].
  String get exitLabel {
    if (exitCode != CliExitCode.clean || reportableViolations.isEmpty) {
      return CliExitCode.labelFor(exitCode);
    }
    return gateRequested ? gatePassedLabel : noGateRequestedLabel;
  }

  /// The summary-line label of a run that exits `0` with findings because
  /// neither `--exit-code` nor `--fail-on-new-violations` was passed and no
  /// organization ceiling applies.
  static const String noGateRequestedLabel = 'no gate requested';

  /// The summary-line label of a run that exits `0` with findings that its
  /// gate let through: `--fail-on-new-violations` with every finding already
  /// in the baseline, or an organization ceiling the run stayed under.
  static const String gatePassedLabel = 'gate passed';
}
