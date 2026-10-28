// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Parsed snapshot of the LintCrux CLI invocation.
///
/// LintCrux's CLI surface is:
///
/// ```text
/// lintcrux [path...] [--top <module>] [--engine <id>]...
///          [--config <overlay.lintcrux>]
///          [--export <format> --out <path>] [--sarif <out.sarif>]
///          [--baseline <file>] [--exit-code] [--fail-on-new-violations]
///          [--constraints <file>]...
///          [--allow-missing-engines] [--quiet] [--help] [--version]
/// ```
///
/// The same snapshot serves two consumers:
/// - the **GUI** (`lib/app.dart` via `cliArgsProvider`), which honors
///   `paths`, `sessionPath`, `workspacePath`, `importFilelistPath`, and
///   `engineBinaryPaths`, and ignores the CI-gate fields; and
/// - the **headless binary** (`bin/lintcrux.dart` via `HeadlessRunner`),
///   which honors everything except the UI-state fields
///   (`sessionPath` / `workspacePath` are meaningless without a window).
///
/// `paths` is the ordered list of positional file arguments. A path may
/// point at:
/// - a `.lintcrux` project file, or
/// - one or more raw RTL source files (`.v`, `.sv`, `.vhd`, `.vhdl`) that
///   form an ad-hoc project.
///
/// Path-kind detection is intentionally deferred — `CliArgs` does not
/// resolve or stat the filesystem. `HeadlessInputResolver` owns that for
/// the CLI, and reports any positional it cannot use rather than dropping
/// it (see `CliExitCode.usage`).
@immutable
class CliArgs {
  /// Creates a [CliArgs] instance.
  const CliArgs({
    this.paths = const <String>[],
    this.configPath,
    this.sarifOutputPath,
    this.sessionPath,
    this.workspacePath,
    this.exitCodeOnFindings = false,
    this.showHelp = false,
    this.showVersion = false,
    this.importFilelistPath,
    this.importEdamPath,
    this.engineBinaryPaths = const <String, String>{},
    this.topModule,
    this.exportFormat,
    this.exportOutputPath,
    this.baselinePath,
    this.failOnNewViolations = false,
    this.ciGateThreshold,
    this.allowMissingEngines = false,
    this.engineIds = const <String>[],
    this.mandatoryEngineIds = const <String>[],
    this.quiet = false,
    this.engineTimeout,
    this.sarifRoot,
    this.relativeTo,
    this.constraintFiles = const <String>[],
    this.parameters = const <String, String>{},
  });

  /// Empty/default args — equivalent to `lintcrux` with no flags.
  static const CliArgs empty = CliArgs();

  /// Positional path arguments, in invocation order.
  final List<String> paths;

  /// Path to the YAML override config file (the `--config` flag), or
  /// `null` if not provided.
  final String? configPath;

  /// Where to write the SARIF output file when `--sarif <out.sarif>` is
  /// passed. `null` means "do not emit SARIF" (the default — the
  /// interactive UI is the only output sink).
  final String? sarifOutputPath;

  /// Path to a `.lintcrux-session` file to apply after project load
  /// when `--session <file>` is passed. `null` means "no session
  /// restore" (the default).
  final String? sessionPath;

  /// Path to a `.lintcrux-workspace` file passed via
  /// `--workspace <path>`. When non-null, the bootstrap loads the
  /// named workspace (replacing the auto-saved workspace document)
  /// before processing any positional `.lintcrux` paths. `null`
  /// (the default) means "use the auto-managed workspace".
  final String? workspacePath;

  /// When `true` (the `--exit-code` flag), the LintCrux process exits
  /// non-zero if any non-suppressed violation is present after the run.
  /// The run pipeline acts on it.
  final bool exitCodeOnFindings;

  /// Whether `--help`/`-h` was passed. Callers should print the usage
  /// block and exit 0 when this is `true`.
  final bool showHelp;

  /// Whether `--version` was passed.
  final bool showVersion;

  /// Path to a Vivado-style `.f` filelist passed via
  /// `--import-filelist <path>`. `null` when the flag is absent. When
  /// non-null, the bootstrap step calls `FilelistImportService` to
  /// emit a `.lintcrux` beside the source and either opens it in the
  /// UI or prints the path in headless mode.
  final String? importFilelistPath;

  /// Path to a FuseSoC/Edalize EDAM (`.eda.yml`) file passed via
  /// `--import-edam <path>`. `null` when the flag is absent. When
  /// non-null, the bootstrap step calls `EdamImportService` to emit a
  /// `.lintcrux` beside the EDAM and either opens it in the UI or
  /// lints it in headless mode — LintCrux's half of the FuseSoC EDAM
  /// integration.
  final String? importEdamPath;

  /// Per-engine custom binary paths supplied via flags like
  /// `--verilator-path`, `--verible-path`, `--ghdl-path` (etc.). Keyed
  /// by [LintEngine.id]. The bootstrap step folds these into
  /// `AppSettings.engineBinaryOverrides` before the app's first run so
  /// CI invocations can override the GUI's stored choices for a single
  /// run without touching settings on disk.
  final Map<String, String> engineBinaryPaths;

  /// Top module / entity name supplied via `--top <module>`.
  ///
  /// Applies to the ad-hoc positional-source-file workflow
  /// (`lintcrux foo.v bar.sv --top top_module`), where there is no
  /// `.lintcrux` file to carry [LintProject.topModule]. When a project
  /// file *is* loaded, this overrides the project's declared top module
  /// for the run so CI can lint one block of a larger design without
  /// editing the committed project file.
  final String? topModule;

  /// Output format requested via `--export <format>`.
  ///
  /// One of `sarif`, `json`, `csv`, `html` — the four formats
  /// `ViolationExporters` can emit. Must be paired with
  /// [exportOutputPath]; an `--export` without an `--out` is a usage
  /// error rather than a silent write to stdout, because a CI step that
  /// meant to produce an upload artifact and produced nothing should
  /// fail loudly.
  final String? exportFormat;

  /// Destination path for `--out <path>`, paired with [exportFormat].
  ///
  /// `--sarif <path>` remains supported as the shorthand for
  /// `--export sarif --out <path>`; the parser normalizes the shorthand
  /// into this pair so downstream code has one code path.
  final String? exportOutputPath;

  /// Baseline file consulted by [failOnNewViolations], supplied via
  /// `--baseline <file>`.
  ///
  /// `null` means "look for `.lintcrux-baseline.json` in the project
  /// root". A baseline file is *written* by LintCrux Pro's baseline
  /// workflow; the open-core CLI only reads it, which is all a CI gate
  /// needs (see `CliBaselineReader`).
  final String? baselinePath;

  /// When `true` (the `--fail-on-new-violations` flag), the process
  /// exits [CliExitCode.newViolations] if any violation is absent from
  /// the baseline.
  ///
  /// Distinct from [exitCodeOnFindings], which fails on *any* surviving
  /// violation. The two compose: pass both to fail on pre-existing debt
  /// with code `1` and on regressions with code `2`.
  final bool failOnNewViolations;

  /// The organization's ceiling on surviving violations, or `null` when no
  /// ceiling applies.
  ///
  /// **Nothing in open core ever populates this**, and that is the point. The
  /// plain gates — `--exit-code` and `--fail-on-new-violations` — ship free in
  /// this binary, and always will: a team gating its own PRs needs no licence
  /// from us. What is Enterprise is the *organization-wide* threshold, read
  /// from the signed `.crux-policy.json` by the Pro CLI, which checks the tier
  /// before it hands a value down. Open core supplies the mechanism that
  /// honours a ceiling; only a licensed build knows what the ceiling is.
  ///
  /// Deliberately **not** a command-line flag. A number an engineer can pass
  /// on the command line is a number they can also raise, which makes it a
  /// preference rather than a policy. The whole value of an org threshold is
  /// that it comes from a signed file the pipeline does not get to edit.
  final int? ciGateThreshold;

  /// When `true` (the `--allow-missing-engines` flag), an engine whose
  /// binary cannot be found is reported and skipped instead of failing
  /// the run with [CliExitCode.runFailed].
  ///
  /// The default is deliberately the strict one. A CI job that asked for
  /// Verilator and silently got zero engines is the "silent false-clean"
  /// failure mode in a different costume.
  final bool allowMissingEngines;

  /// Engine ids to run, supplied by repeating `--engine <id>`.
  ///
  /// Empty (the default) means "the project's `enabledEngineIds`, or
  /// every registered engine when the project does not narrow the set".
  /// Non-empty replaces that selection for this invocation — the usual
  /// CI shape, where the runner image only has one or two engines
  /// installed.
  final List<String> engineIds;

  /// Engine ids the organization requires on every run, or empty when none
  /// are mandated.
  ///
  /// A restriction, not a default: the planner adds these to the run
  /// whatever [engineIds] or the project's `enabledEngineIds` say, and the
  /// headless runner refuses the run (exit 3) when one of them is
  /// unavailable, whatever [allowMissingEngines] says. A mandate a pipeline
  /// could opt out of would not be one.
  ///
  /// **Nothing in open core ever populates this**, for the same reason as
  /// [ciGateThreshold]: it is read from the organization's signed
  /// `.crux-policy.json` by the Pro CLI, which checks the tier before it
  /// hands a value down, and it is deliberately not a command-line flag.
  /// Open core supplies the mechanism that honours a mandate; only a
  /// licensed build knows what is mandated.
  final List<String> mandatoryEngineIds;

  /// When `true` (the `--quiet` flag), the headless runner prints only
  /// the machine-readable summary line and any diagnostics, suppressing
  /// the per-violation listing. Exit codes are unaffected.
  final bool quiet;

  /// Per-engine wall-clock budget supplied via `--engine-timeout <seconds>`,
  /// or `null` for the headless runner's default (300 s).
  ///
  /// Yosys-based engines flatten the whole design, and on a full SoC that
  /// can take longer than five minutes; without this a headless run could
  /// not be made to wait. The desktop app has its own setting and ignores
  /// this field.
  final Duration? engineTimeout;

  /// The directory SARIF paths are written relative to and declared as
  /// `%SRCROOT%`, supplied via `--sarif-root <dir>`; `null` means the
  /// nearest enclosing git repository root of the project, else the project
  /// root.
  ///
  /// GitHub code scanning resolves a relative URI against the repository
  /// root and ignores `originalUriBaseIds`, so a project kept in a
  /// subfolder had every alert recorded at the wrong path. The flag covers
  /// a CI layout whose checkout root is not the git root.
  final String? sarifRoot;

  /// The directory JSON, CSV and HTML export paths are written relative to,
  /// supplied via `--relative-to <dir>`; `null` means the project root.
  ///
  /// Those exports used to carry the absolute paths the engines report, so a
  /// report attached to someone else's issue published the local directory
  /// layout. A path outside the directory stays absolute, as in SARIF.
  final String? relativeTo;

  /// Pin-constraint files supplied by repeating `--constraints <file>`, added
  /// to the project's own `constraintFiles` for this run.
  ///
  /// The format of each follows its extension (`.pcf`, `.lpf`, `.cst`); the
  /// parser refuses any other extension rather than guessing.
  final List<String> constraintFiles;

  /// Top-level parameter overrides supplied by repeating
  /// `--param NAME=VALUE`, applied on top of the project's own `parameters`
  /// for this run: a CI job lints each configuration of a parameterised
  /// core from one project file.
  final Map<String, String> parameters;

  /// Returns a copy with overridden fields.
  CliArgs copyWith({
    List<String>? paths,
    String? configPath,
    String? sarifOutputPath,
    String? sessionPath,
    String? workspacePath,
    bool? exitCodeOnFindings,
    bool? showHelp,
    bool? showVersion,
    String? importFilelistPath,
    String? importEdamPath,
    Map<String, String>? engineBinaryPaths,
    String? topModule,
    String? exportFormat,
    String? exportOutputPath,
    String? baselinePath,
    bool? failOnNewViolations,
    int? ciGateThreshold,
    bool? allowMissingEngines,
    List<String>? engineIds,
    List<String>? mandatoryEngineIds,
    bool? quiet,
    Duration? engineTimeout,
    String? sarifRoot,
    String? relativeTo,
    List<String>? constraintFiles,
    Map<String, String>? parameters,
  }) {
    return CliArgs(
      parameters: parameters ?? this.parameters,
      constraintFiles: constraintFiles ?? this.constraintFiles,
      paths: paths ?? this.paths,
      configPath: configPath ?? this.configPath,
      sarifOutputPath: sarifOutputPath ?? this.sarifOutputPath,
      sessionPath: sessionPath ?? this.sessionPath,
      workspacePath: workspacePath ?? this.workspacePath,
      exitCodeOnFindings: exitCodeOnFindings ?? this.exitCodeOnFindings,
      showHelp: showHelp ?? this.showHelp,
      showVersion: showVersion ?? this.showVersion,
      importFilelistPath: importFilelistPath ?? this.importFilelistPath,
      importEdamPath: importEdamPath ?? this.importEdamPath,
      engineBinaryPaths: engineBinaryPaths ?? this.engineBinaryPaths,
      topModule: topModule ?? this.topModule,
      exportFormat: exportFormat ?? this.exportFormat,
      exportOutputPath: exportOutputPath ?? this.exportOutputPath,
      baselinePath: baselinePath ?? this.baselinePath,
      failOnNewViolations: failOnNewViolations ?? this.failOnNewViolations,
      ciGateThreshold: ciGateThreshold ?? this.ciGateThreshold,
      allowMissingEngines: allowMissingEngines ?? this.allowMissingEngines,
      engineIds: engineIds ?? this.engineIds,
      mandatoryEngineIds: mandatoryEngineIds ?? this.mandatoryEngineIds,
      quiet: quiet ?? this.quiet,
      engineTimeout: engineTimeout ?? this.engineTimeout,
      sarifRoot: sarifRoot ?? this.sarifRoot,
      relativeTo: relativeTo ?? this.relativeTo,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CliArgs) return false;
    if (other.configPath != configPath) return false;
    if (other.sarifOutputPath != sarifOutputPath) return false;
    if (other.sessionPath != sessionPath) return false;
    if (other.workspacePath != workspacePath) return false;
    if (other.exitCodeOnFindings != exitCodeOnFindings) return false;
    if (other.showHelp != showHelp) return false;
    if (other.showVersion != showVersion) return false;
    if (other.importFilelistPath != importFilelistPath) return false;
    if (other.importEdamPath != importEdamPath) return false;
    if (other.paths.length != paths.length) return false;
    for (var i = 0; i < paths.length; i++) {
      if (other.paths[i] != paths[i]) return false;
    }
    if (other.engineBinaryPaths.length != engineBinaryPaths.length) {
      return false;
    }
    for (final entry in engineBinaryPaths.entries) {
      if (other.engineBinaryPaths[entry.key] != entry.value) return false;
    }
    if (other.topModule != topModule) return false;
    if (other.exportFormat != exportFormat) return false;
    if (other.exportOutputPath != exportOutputPath) return false;
    if (other.baselinePath != baselinePath) return false;
    if (other.failOnNewViolations != failOnNewViolations) return false;
    if (other.allowMissingEngines != allowMissingEngines) return false;
    if (other.quiet != quiet) return false;
    if (other.engineTimeout != engineTimeout) return false;
    if (other.sarifRoot != sarifRoot) return false;
    if (other.relativeTo != relativeTo) return false;
    if (other.parameters.length != parameters.length) return false;
    for (final entry in parameters.entries) {
      if (other.parameters[entry.key] != entry.value) return false;
    }
    if (other.constraintFiles.length != constraintFiles.length) return false;
    for (var i = 0; i < constraintFiles.length; i++) {
      if (other.constraintFiles[i] != constraintFiles[i]) return false;
    }
    if (other.engineIds.length != engineIds.length) return false;
    for (var i = 0; i < engineIds.length; i++) {
      if (other.engineIds[i] != engineIds[i]) return false;
    }
    if (other.mandatoryEngineIds.length != mandatoryEngineIds.length) {
      return false;
    }
    for (var i = 0; i < mandatoryEngineIds.length; i++) {
      if (other.mandatoryEngineIds[i] != mandatoryEngineIds[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    final ks = engineBinaryPaths.keys.toList()..sort();
    final engineHash = Object.hashAll(
      ks.expand((k) => [k, engineBinaryPaths[k]]),
    );
    return Object.hash(
      Object.hashAll(paths),
      configPath,
      sarifOutputPath,
      sessionPath,
      workspacePath,
      exitCodeOnFindings,
      showHelp,
      showVersion,
      importFilelistPath,
      importEdamPath,
      engineHash,
      topModule,
      exportFormat,
      exportOutputPath,
      baselinePath,
      failOnNewViolations,
      allowMissingEngines,
      quiet,
      // Object.hash takes at most twenty arguments.
      Object.hash(
        engineTimeout,
        sarifRoot,
        relativeTo,
        Object.hashAllUnordered(
          parameters.entries.map((e) => Object.hash(e.key, e.value)),
        ),
        Object.hashAll(mandatoryEngineIds),
        Object.hashAll(constraintFiles),
      ),
      Object.hashAll(engineIds),
    );
  }

  @override
  String toString() =>
      'CliArgs(paths: $paths, config: $configPath, sarif: $sarifOutputPath, '
      'session: $sessionPath, workspace: $workspacePath, '
      'exitCode: $exitCodeOnFindings, '
      'help: $showHelp, version: $showVersion, '
      'importFilelist: $importFilelistPath, '
      'importEdam: $importEdamPath, top: $topModule, '
      'export: $exportFormat, out: $exportOutputPath, '
      'baseline: $baselinePath, failOnNew: $failOnNewViolations, '
      'allowMissingEngines: $allowMissingEngines, engines: $engineIds, '
      'mandatoryEngines: $mandatoryEngineIds, '
      'quiet: $quiet, engineTimeout: $engineTimeout, sarifRoot: $sarifRoot, '
      'relativeTo: $relativeTo, constraints: $constraintFiles, '
      'parameters: $parameters)';
}
