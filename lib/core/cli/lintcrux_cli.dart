// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:lintcrux/core/app_info/build_info.dart';
import 'package:lintcrux/core/cli/cli_args.dart';
import 'package:lintcrux/core/cli/cli_args_parser.dart';
import 'package:lintcrux/core/cli/cli_exit_codes.dart';
import 'package:lintcrux/domain/interfaces/violation_transformer.dart';
import 'package:lintcrux/services/cli/cli_args.dart' as launch_cli;
import 'package:lintcrux/services/engines/default_engine_registry.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/headless/headless_reporter.dart';
import 'package:lintcrux/services/headless/headless_run_result.dart';
import 'package:lintcrux/services/headless/headless_runner.dart';
import 'package:lintcrux/services/headless/headless_signal_guard.dart';
import 'package:lintcrux/services/import/edam_import_service.dart';
import 'package:lintcrux/services/import/edam_reader.dart'
    show EdamImportException;
import 'package:lintcrux/services/import/filelist_import_service.dart';
import 'package:lintcrux/services/import/filelist_reader.dart'
    show FilelistImportException;
import 'package:lintcrux/services/telemetry/headless_telemetry.dart';

/// The whole headless command, minus the two things a `lib/` file must
/// not do: read the real `argv` and call `exit`.
///
/// `bin/lintcrux.dart` is four lines around this class. Keeping the
/// logic here is what lets `flutter test` cover the exit-code contract
/// directly, instead of the tests being limited to spawning a compiled
/// binary and squinting at `$?`. (The compiled binary *is* also
/// exercised end-to-end — see `verification/VERIFICATION_GUIDE.md` §CLI
/// — but a contract this load-bearing should not be reachable only
/// through a build step.)
///
/// The Pro overlay's CLI subclasses nothing: it constructs its own
/// [LintcruxCli] with a richer [extraTransformers] list and its own
/// subcommand table. This class is the open-core capability, free for
/// everyone.
class LintcruxCli {
  /// Creates a [LintcruxCli].
  ///
  /// [registry] defaults to the open-core engine set. The Pro CLI passes
  /// a registry that also carries Pro engines. [extraTransformers] are
  /// appended to the open-core transformer chain (severity overrides →
  /// source pragmas → these), which is where the Pro managed-waiver
  /// transformer goes.
  ///
  /// [telemetryResolver] is the headless-consent seam. It defaults to
  /// [HeadlessTelemetry.resolve], which reads the same on-disk store the
  /// desktop app writes and yields a reporter that transmits **only** on a
  /// stored `enabled`. Tests replace it to point at a temp store; the Pro CLI
  /// replaces it to pass its resolved license tier.
  ///
  /// [versionLine] and [usagePreamble] are for a host binary built on this
  /// class: `--version` must print the name a user types to run *that*
  /// binary, and its `--help` has options of its own to name ahead of these.
  ///
  /// [signalGuard] replaces the default guard outright; [installSignalReaper]
  /// only configures the default one.
  LintcruxCli({
    EngineRegistry? registry,
    this.extraTransformers = const <ViolationTransformer>[],
    this.installSignalReaper = true,
    Future<HeadlessTelemetry> Function()? telemetryResolver,
    this.argsDecorator,
    this.versionLine = LintCruxBuildInfo.versionLine,
    this.usagePreamble,
    HeadlessSignalGuard? signalGuard,
  }) : registry = registry ?? defaultEngineRegistry(),
       telemetryResolver = telemetryResolver ?? _defaultTelemetryResolver,
       signalGuard =
           signalGuard ?? HeadlessSignalGuard(enabled: installSignalReaper);

  static Future<HeadlessTelemetry> _defaultTelemetryResolver() =>
      HeadlessTelemetry.resolve(
        appVersion: LintCruxBuildInfo.productVersion,
      );

  /// Engines available to this invocation.
  final EngineRegistry registry;

  /// Extra violation transformers layered onto the open-core chain.
  final List<ViolationTransformer> extraTransformers;

  /// Whether the default [signalGuard] installs its handlers. Tests turn it
  /// off so they do not fight over the process-wide signal handlers.
  final bool installSignalReaper;

  /// Reaps the engines and exits `128 + N` when the run is cancelled.
  final HeadlessSignalGuard signalGuard;

  /// The banner `--version` prints: `<name> <semver>`.
  final String versionLine;

  /// Printed ahead of the usage block by `--help`, or `null` for none.
  final String? usagePreamble;

  /// A last chance to adjust the parsed arguments before the pipeline runs,
  /// or `null` (the open-core default) to use them exactly as typed.
  ///
  /// **The seam exists for one thing: a setting that must not be a flag.**
  /// The organization's `ciGateThreshold` comes from a signed policy file, and
  /// the Pro CLI resolves it here rather than the parser learning about it —
  /// a threshold with a command-line flag is a threshold a pipeline can raise,
  /// which would make it a preference rather than a policy. Keeping it out of
  /// [CliArgsParser] also keeps Enterprise vocabulary out of open core's
  /// `--help`, which the Pro subcommands already do for their own options.
  ///
  /// Runs after `--help` / `--version` short-circuit and before any engine, so
  /// a decorator never delays the two commands that must always be instant.
  /// It may write to [stderrSink] — the Pro CLI does, when a threshold was
  /// configured and the tier does not include it, because an administrator
  /// whose signed ceiling is being ignored needs to know the licence is why.
  final CliArgs Function(CliArgs args, void Function(String) stderrSink)?
  argsDecorator;

  /// Resolves this invocation's [HeadlessTelemetry].
  ///
  /// Called once per `--help`-and-`--version`-free run, immediately before the
  /// pipeline. It reads consent and nothing else — it never prompts, never
  /// writes, and on a machine that has not stored an affirmative consent it
  /// returns a reporter that performs no I/O at all.
  final Future<HeadlessTelemetry> Function() telemetryResolver;

  /// Parses [args] the way [run] does: strictly, after removing the desktop
  /// app's launch flags.
  ///
  /// `--reset` and `--no-restore` recover a wedged desktop session. A shell
  /// alias or wrapper script shared between the app and this binary passes
  /// them here as well, and there is no session here to reset, so they are
  /// accepted and do nothing — rejecting them with 64 broke those wrappers.
  /// Every other unknown flag is still a usage error.
  static CliArgsParseResult _parse(List<String> args) =>
      CliArgsParser().parse(launch_cli.stripLaunchFlags(args));

  /// Whether [run] would answer [args] with the usage block or the version
  /// line, and do nothing else.
  ///
  /// For a host that must answer those two before work of its own — looking
  /// up a licence, say — and needs the same decision [run] will make, not an
  /// approximation of it: a host that skipped its work for a command line
  /// that then went on to lint would lint without it.
  static bool isHelpOrVersion(List<String> args) {
    final parsed = _parse(args);
    return parsed.isSuccess &&
        (parsed.args!.showHelp || parsed.args!.showVersion);
  }

  /// Runs the command described by [args] and returns the exit code.
  ///
  /// [stdoutSink] / [stderrSink] receive one call per line. Injected so
  /// tests capture output without touching the real streams.
  Future<int> run(
    List<String> args, {
    required void Function(String line) stdoutSink,
    required void Function(String line) stderrSink,
  }) async {
    final parsed = _parse(args);
    if (!parsed.isSuccess) {
      stderrSink('lintcrux: ${parsed.error}');
      stderrSink('');
      stderrSink(parsed.usage);
      return CliExitCode.usage;
    }
    var cliArgs = parsed.args!;

    if (cliArgs.showHelp) {
      final preamble = usagePreamble;
      if (preamble != null) stdoutSink(preamble);
      stdoutSink(parsed.usage);
      return CliExitCode.clean;
    }
    if (cliArgs.showVersion) {
      stdoutSink(versionLine);
      return CliExitCode.clean;
    }

    final decorate = argsDecorator;
    if (decorate != null) cliArgs = decorate(cliArgs, stderrSink);

    // `--import-filelist` converts a Vivado-style `.f` into a
    // `.lintcrux` beside it, then the emitted project joins the
    // positional list and gets linted like any other. Same behavior as
    // the GUI front door, same exit code on failure — a CI job that uses
    // the import as a filelist-health check keeps working.
    if (cliArgs.importFilelistPath != null &&
        cliArgs.importFilelistPath!.isNotEmpty) {
      try {
        const service = FilelistImportService();
        final imported = service.importFilelist(
          filelistPath: cliArgs.importFilelistPath!,
        );
        stdoutSink('Imported filelist → ${imported.projectFilePath}');
        cliArgs = cliArgs.copyWith(
          paths: <String>[...cliArgs.paths, imported.projectFilePath],
        );
      } on FilelistImportException catch (e) {
        stderrSink('lintcrux: ${e.message}');
        return CliExitCode.dataError;
      }
    }

    // `--import-edam` converts a FuseSoC/Edalize EDAM (`.eda.yml`)
    // into a `.lintcrux` beside it — same contract as
    // `--import-filelist`: the emitted project joins the positional
    // list and is linted like any other, and a broken input exits 65.
    // Together with `fusesoc run --target=lint --setup <core>` this is
    // the complete FuseSoC → LintCrux pipeline.
    if (cliArgs.importEdamPath != null && cliArgs.importEdamPath!.isNotEmpty) {
      try {
        const service = EdamImportService();
        final imported = service.importEdam(
          edamPath: cliArgs.importEdamPath!,
        );
        for (final warning in imported.warnings) {
          stderrSink('lintcrux: warning: $warning');
        }
        stdoutSink('Imported EDAM → ${imported.projectFilePath}');
        cliArgs = cliArgs.copyWith(
          paths: <String>[...cliArgs.paths, imported.projectFilePath],
        );
      } on EdamImportException catch (e) {
        stderrSink('lintcrux: ${e.message}');
        return CliExitCode.dataError;
      }
    }

    // Reap any engine subprocess if the job is cancelled. The GUI does
    // the equivalent from `AppLifecycleState.detached`; a headless
    // process only ever learns it is going away from a signal.
    return signalGuard.run(stderrSink: stderrSink, () async {
      // Resolved before the run so the counters have somewhere to go, and
      // resolved even when consent is `unset` — `HeadlessTelemetry` is the
      // thing that knows the answer is "record nothing", and a caller that
      // branched on consent here would be a second place the rule could go
      // wrong.
      final telemetry = await telemetryResolver();
      try {
        final result = await _execute(cliArgs, telemetry);
        final reporter = HeadlessReporter(
          relativeTo: Directory.current.path,
          quiet: cliArgs.quiet,
        );
        reporter.stderrLines(result).forEach(stderrSink);
        reporter.stdoutLines(result).forEach(stdoutSink);
        return result.exitCode;
      } finally {
        // Sent here rather than left in a queue for a GUI this machine may
        // not have — see `HeadlessTelemetry`'s "flush decision". Bounded,
        // never throwing, and a no-op on every run that did not record
        // anything, which is every run without a stored affirmative consent.
        await telemetry.flush();
      }
    });
  }

  /// Runs the pipeline. Split out so the Pro CLI can wrap it.
  Future<HeadlessRunResult> _execute(
    CliArgs args,
    HeadlessTelemetry telemetry,
  ) {
    final runner = HeadlessRunner(
      registry: registry,
      extraTransformers: extraTransformers,
      telemetry: telemetry,
    );
    return runner.run(args);
  }
}
