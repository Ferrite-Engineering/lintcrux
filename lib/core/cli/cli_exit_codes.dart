// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The exit-code contract of the headless `lintcrux` binary
/// (`bin/lintcrux.dart`).
///
/// A CI job must be able to distinguish *"your RTL has lint findings"*
/// from *"the linter itself did not work"*. Collapsing those two into a
/// single non-zero exit is the failure mode that makes
/// `verible-verilog-lint`'s own exit code useless to us — it exits `1`
/// **because it found violations**, so "non-zero" alone carries no
/// information. See the `EngineRunFailedException` doc comment in
/// `lib/domain/interfaces/lint_engine.dart` for the sibling rule on the
/// engine side ("exit≠0 with nothing parseable is a failure").
///
/// The codes below are disjoint and ordered by escalation: a run that
/// both found violations *and* had an engine fail reports the failure,
/// because the violation count from a broken run cannot be trusted.
///
/// ```text
///   0  clean          nothing to report, or findings present but no gate requested
///   1  violations     --exit-code was passed and ≥1 non-suppressed violation remains
///   2  newViolations  --fail-on-new-violations was passed and ≥1 violation is
///                     absent from the baseline
///   3  runFailed      an engine failed / timed out / was unavailable, or the
///                     named project could not be loaded (unparseable, no
///                     sources, a listed source missing), or the export could
///                     not be written — the violation count is NOT trustworthy
///   4  overThreshold  the organization's `ciGateThreshold` was configured and
///                     the surviving violation count exceeds it
///  64  usage          bad command line: unknown flag, missing value, a
///                     positional argument that is neither a project nor a
///                     lintable source file, or a path that does not exist
///  65  dataError      --import-filelist / --import-edam could not convert input
/// ```
///
/// The low codes are small and contiguous because a workflow reads
/// better as `if: steps.lint.outcome == 2` than as a `sysexits.h`
/// number. `64` and `65` keep the values the GUI front door has always
/// returned for the same two conditions (see `bootstrap` in
/// `lib/app.dart`), so the two entry points never disagree.
class CliExitCode {
  const CliExitCode._();

  /// The run completed and there is nothing to fail on.
  ///
  /// Emitted when no violations remain after waivers/baseline, and also
  /// when violations *are* present but neither `--exit-code` nor
  /// `--fail-on-new-violations` was requested — a bare `lintcrux
  /// project.lintcrux` is a reporting command, not a gate.
  static const int clean = 0;

  /// `--exit-code` was requested and at least one non-suppressed
  /// violation survived the transformer chain.
  static const int violations = 1;

  /// `--fail-on-new-violations` was requested and at least one violation
  /// is not present in the baseline.
  ///
  /// Takes precedence over [violations]: when both gates are requested
  /// and there are new violations, the more specific code wins so a CI
  /// job can branch on "regression" versus "pre-existing debt".
  static const int newViolations = 2;

  /// The run itself did not work.
  ///
  /// Covers: an engine reported `EngineRunPhase.failed` (non-zero exit
  /// with nothing parseable) or `EngineRunPhase.unavailable` (binary not
  /// found, unless `--allow-missing-engines` was passed), an engine
  /// exceeded its watchdog budget, the `.lintcrux` project named on the
  /// command line exists but could not be read or parsed, declares no
  /// sources, or lists a source that is missing, the `--config` overlay was
  /// malformed, the requested
  /// baseline file was corrupt, or the `--out` export could not be
  /// written.
  ///
  /// Whatever violation count was printed alongside this code is a
  /// partial result and must not be treated as a clean bill of health.
  static const int runFailed = 3;

  /// The organization's `ciGateThreshold` was configured and the surviving
  /// violation count is above it.
  ///
  /// **Distinct from [violations] and [newViolations] on purpose, and it
  /// outranks both.** Those two are the team's own gates: "we have findings"
  /// and "we regressed against our own baseline". This one is an organization
  /// policy — an absolute ceiling written into the signed `.crux-policy.json`
  /// — and being above it blocks whether or not this change caused it. A
  /// regression that stays under the ceiling is a softer signal than a run
  /// that breaches it, so the ceiling wins the escalation.
  ///
  /// Reported separately because the two need different responses. Code `2`
  /// says *"you added these; take them back out."* Code `4` says *"the
  /// project is over the organization's budget"*, which may be nobody on this
  /// PR's fault and may need a conversation rather than a revert. Collapsing
  /// them into one number would make a CI log unable to tell a developer
  /// which of those they are looking at.
  ///
  /// Enterprise. The plain gates above ship free in the open-core binary; what
  /// this adds is the *organization-wide* threshold, and the open-core runner
  /// honours it only when something hands it one.
  static const int overThreshold = 4;

  /// The command line could not be honored. `EX_USAGE` from
  /// `sysexits.h`, and the code the GUI front door already returns for
  /// a parse failure.
  ///
  /// Unknown flag, missing option value, `--export` without `--out`, an
  /// unrecognized export format, an unknown `--engine` id, no positional
  /// argument, a positional argument that is neither a `.lintcrux` project
  /// nor a lintable HDL source file, or a path that does not exist.
  ///
  /// The last case matters: before the headless runner existed, a
  /// non-`.lintcrux` positional was silently dropped, so
  /// `lintcrux typo.sv` reported a clean run over zero files. Silent
  /// success on an unusable input is the same defect class as a silent
  /// clean run from a broken engine.
  static const int usage = 64;

  /// `--import-filelist` could not read or convert the `.f` filelist,
  /// or `--import-edam` could not read or convert the `.eda.yml` EDAM.
  /// `EX_DATAERR` from `sysexits.h`, matching the GUI front door.
  static const int dataError = 65;

  /// Every code the binary can return, for exhaustiveness tests and for
  /// the documentation generator.
  static const List<int> all = <int>[
    clean,
    violations,
    newViolations,
    runFailed,
    overThreshold,
    usage,
    dataError,
  ];

  /// A short, stable, machine-greppable label for [code]. Printed by the
  /// reporter's final line so a CI log makes the contract self-evident
  /// without the reader consulting this file.
  static String labelFor(int code) {
    switch (code) {
      case clean:
        return 'clean';
      case violations:
        return 'violations';
      case newViolations:
        return 'new-violations';
      case runFailed:
        return 'run-failed';
      case overThreshold:
        return 'over-threshold';
      case usage:
        return 'usage-error';
      case dataError:
        return 'data-error';
      default:
        return 'unknown';
    }
  }
}
