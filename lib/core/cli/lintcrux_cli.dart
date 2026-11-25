// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crux_mcp/crux_mcp.dart' hide HeadlessTelemetry;
import 'package:lintcrux/core/app_info/build_info.dart';
import 'package:lintcrux/core/cli/cli_args.dart';
import 'package:lintcrux/core/cli/cli_args_parser.dart';
import 'package:lintcrux/core/cli/cli_exit_codes.dart';
import 'package:lintcrux/domain/interfaces/violation_transformer.dart';
import 'package:lintcrux/domain/models/engine_run_status.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/headless/lint_document.dart';
import 'package:lintcrux/headless/lintcrux_mcp.dart';
import 'package:lintcrux/headless/rule_command.dart';
import 'package:lintcrux/headless/waivers_command.dart';
import 'package:lintcrux/services/baseline/baseline_filter.dart';
import 'package:lintcrux/services/cli/cli_args.dart' as launch_cli;
import 'package:lintcrux/services/engines/default_engine_registry.dart';
import 'package:lintcrux/services/engines/engine_binary_ids.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/headless/cli_baseline_reader.dart';
import 'package:lintcrux/services/headless/headless_export_writer.dart';
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

/// The parts of a lint answer a binary leaves out, as `licence.withheld`
/// warnings, given the project and whether the CDC engine ran.
typedef LintWithheldParts =
    List<McpDiagnostic> Function(LintProject project, {required bool cdcRan});

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
/// Besides the bare lint command line it answers three subcommands, each
/// with `--json` writing `crux_mcp`'s document: `rule` and `waivers`
/// (`lib/headless/`), and `mcp`, which serves `lint`, `rule` and `waivers`
/// as Model Context Protocol tools on stdio. Each tool runs the command's
/// own code here, so its text is byte for byte what the command writes.
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
  ///
  /// [exportWriter] writes `--export`. Open core passes the plain writer: it
  /// resolves no licence, so its HTML report carries no mark. A host that
  /// resolves one passes a writer carrying the educational-licence mark.
  ///
  /// [program] is the `tool` every `--json` document names. [withheld] adds
  /// the `licence.withheld` warnings of the parts this binary leaves out;
  /// `bin/lintcrux.dart` passes [openCoreWithheld], and `null` adds none.
  /// [mcpTelemetry] makes the `mcp` server's counter (`null` counts
  /// nothing). [classify] maps a run to its outcome and exists for the
  /// mutation proof only.
  LintcruxCli({
    EngineRegistry? registry,
    this.extraTransformers = const <ViolationTransformer>[],
    this.exportWriter = const HeadlessExportWriter(),
    this.installSignalReaper = true,
    Future<HeadlessTelemetry> Function()? telemetryResolver,
    this.argsDecorator,
    this.versionLine = LintCruxBuildInfo.versionLine,
    this.usagePreamble,
    HeadlessSignalGuard? signalGuard,
    this.program = const McpProgram(
      name: kLintcruxProgramName,
      version: LintCruxBuildInfo.productVersion,
    ),
    this.withheld,
    McpTelemetry? Function()? mcpTelemetry,
    this.classify = classifyLintRun,
  }) : registry = registry ?? defaultEngineRegistry(),
       telemetryResolver = telemetryResolver ?? _defaultTelemetryResolver,
       signalGuard =
           signalGuard ?? HeadlessSignalGuard(enabled: installSignalReaper),
       _mcpTelemetry = mcpTelemetry ?? lintcruxMcpTelemetry;

  static Future<HeadlessTelemetry> _defaultTelemetryResolver() =>
      HeadlessTelemetry.resolve(
        appVersion: LintCruxBuildInfo.productVersion,
      );

  /// Engines available to this invocation.
  final EngineRegistry registry;

  /// Extra violation transformers layered onto the open-core chain.
  final List<ViolationTransformer> extraTransformers;

  /// Writes the `--export` artifact.
  final HeadlessExportWriter exportWriter;

  /// Whether the default [signalGuard] installs its handlers. Tests turn it
  /// off so they do not fight over the process-wide signal handlers.
  final bool installSignalReaper;

  /// Reaps the engines and exits `128 + N` when the run is cancelled.
  final HeadlessSignalGuard signalGuard;

  /// The banner `--version` prints: `<name> <semver>`.
  final String versionLine;

  /// Printed ahead of the usage block by `--help`, or `null` for none.
  final String? usagePreamble;

  /// The program every `--json` document and the `mcp` server name.
  final McpProgram program;

  /// The `licence.withheld` warnings of the parts this binary leaves out of
  /// a lint answer, or `null` for none.
  final LintWithheldParts? withheld;

  /// Maps a run to its outcome: [classifyLintRun], except in the test that
  /// proves a broken mapping is caught.
  final LintRunClassifier classify;

  final McpTelemetry? Function() _mcpTelemetry;

  /// The last lint run the `mcp` server made, for a later page of it.
  _LintPage? _lastPage;

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

  /// The subcommands, each answered before the lint parser sees the
  /// command line. None is a usable lint positional (no extension), so a
  /// project or source file can never be read as one.
  static const List<String> subcommands = <String>[
    kRuleCommand,
    kWaiversCommand,
    'mcp',
  ];

  static String? _subcommandOf(List<String> args) =>
      args.isNotEmpty && subcommands.contains(args.first) ? args.first : null;

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
    if (_subcommandOf(args) != null) {
      return args.contains('--help') || args.contains('-h');
    }
    final parsed = _parse(args);
    return parsed.isSuccess &&
        (parsed.args!.showHelp || parsed.args!.showVersion);
  }

  /// Runs the command described by [args] and returns the exit code.
  ///
  /// [stdoutSink] / [stderrSink] receive one call per line. Injected so
  /// tests capture output without touching the real streams. `mcp` reads
  /// requests from [input] and writes answers to [output] (the process's
  /// stdin and stdout unless given).
  Future<int> run(
    List<String> args, {
    required void Function(String line) stdoutSink,
    required void Function(String line) stderrSink,
    Stream<List<int>>? input,
    StreamSink<List<int>>? output,
  }) async {
    final subcommand = _subcommandOf(args);
    if (subcommand == 'mcp') {
      return await _serve(
        args.sublist(1),
        stdoutSink: stdoutSink,
        stderrSink: stderrSink,
        input: input,
        output: output,
      );
    }
    if (subcommand != null) {
      return await _subcommand(
        subcommand,
        args.sublist(1),
        stdoutSink: stdoutSink,
        stderrSink: stderrSink,
      );
    }

    final parsed = _parse(args);
    if (!parsed.isSuccess) {
      stderrSink('lintcrux: ${parsed.error}');
      stderrSink('');
      stderrSink(parsed.usage);
      if (args.contains('--${CliArgsParser.kJsonFlag}')) {
        _writeDocument(
          stdoutSink,
          McpDocument.usage(
            tool: program,
            command: kLintCommand,
            message: parsed.error!,
          ),
        );
      }
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

    // With --json, stdout carries the document and nothing else.
    final noteSink = cliArgs.json ? stderrSink : stdoutSink;
    int importFailed(String message) {
      stderrSink('lintcrux: $message');
      if (cliArgs.json) {
        _writeDocument(
          stdoutSink,
          McpDocument(
            tool: program,
            command: kLintCommand,
            outcome: McpOutcome.inputError,
            diagnostics: <McpDiagnostic>[
              McpDiagnostic.error('input.import', message),
            ],
          ),
        );
      }
      return CliExitCode.dataError;
    }

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
        noteSink('Imported filelist → ${imported.projectFilePath}');
        cliArgs = cliArgs.copyWith(
          paths: <String>[...cliArgs.paths, imported.projectFilePath],
        );
      } on FilelistImportException catch (e) {
        return importFailed(e.message);
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
        noteSink('Imported EDAM → ${imported.projectFilePath}');
        cliArgs = cliArgs.copyWith(
          paths: <String>[...cliArgs.paths, imported.projectFilePath],
        );
      } on EdamImportException catch (e) {
        return importFailed(e.message);
      }
    }

    final runArgs = cliArgs;
    // Reap any engine subprocess if the job is cancelled. The GUI does
    // the equivalent from `AppLifecycleState.detached`; a headless
    // process only ever learns it is going away from a signal.
    return await signalGuard.run(stderrSink: stderrSink, () async {
      // Resolved before the run so the counters have somewhere to go, and
      // resolved even when consent is `unset` — `HeadlessTelemetry` is the
      // thing that knows the answer is "record nothing", and a caller that
      // branched on consent here would be a second place the rule could go
      // wrong.
      final telemetry = await telemetryResolver();
      try {
        final run = await _lintRun(runArgs, telemetry);
        final result = run.result;
        final reporter = HeadlessReporter(
          relativeTo: Directory.current.path,
          quiet: runArgs.quiet,
        );
        reporter.stderrLines(result).forEach(stderrSink);
        if (runArgs.json) {
          _writeDocument(stdoutSink, _lintDocument(run, runArgs));
        } else {
          reporter.stdoutLines(result).forEach(stdoutSink);
        }
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

  /// Writes [document] as the whole of stdout: [McpDocument.render] ends in
  /// the newline [sink] adds.
  static void _writeDocument(void Function(String) sink, McpDocument document) {
    final text = document.render();
    sink(text.substring(0, text.length - 1));
  }

  /// Runs the pipeline. Split out so the Pro CLI can wrap it.
  Future<HeadlessRunResult> _execute(
    CliArgs args,
    HeadlessTelemetry? telemetry,
  ) {
    final runner = HeadlessRunner(
      registry: registry,
      extraTransformers: extraTransformers,
      exportWriter: exportWriter,
      telemetry: telemetry,
      engineTimeout: args.engineTimeout ?? HeadlessRunner.defaultEngineTimeout,
      yosysTimeLimit: HeadlessRunner.yosysTimeLimitFor(args),
    );
    return runner.run(args);
  }

  /// A run, and, for a `--json` one, what its document needs beyond the
  /// result: the engines' versions, the design's fingerprint, each
  /// finding's baseline state and the warnings the caller adds.
  Future<_LintRun> _lintRun(CliArgs args, HeadlessTelemetry? telemetry) async {
    final result = await _execute(args, telemetry);
    if (!args.json) return _LintRun(result);
    final project = result.project;
    final ran = result.statuses.isNotEmpty;
    if (!ran || project == null) return _LintRun(result);
    final (baseline, baselineWarnings) = await _baselineView(result, args);
    final cdc = result.statuses['cdc'];
    return _LintRun(
      result,
      engines: await _engineVersions(result, args),
      design: lintSourcesFingerprint(project),
      baseline: baseline,
      extra: <McpDiagnostic>[
        ...?withheld?.call(
          project,
          cdcRan: cdc != null && cdc.phase == EngineRunPhase.completed,
        ),
        ...baselineWarnings,
      ],
    );
  }

  McpDocument _lintDocument(_LintRun run, CliArgs args) => buildLintDocument(
    program: program,
    result: run.result,
    limit: args.limit ?? CliArgsParser.kDefaultLimit,
    offset: args.offset ?? 0,
    engines: run.engines,
    design: run.design,
    baseline: run.baseline,
    extra: run.extra,
    classify: classify,
  );

  /// Each engine that ran, with the version its binary reports (`unknown`
  /// when it reports none within ten seconds). The binary's path is not
  /// known here: it is found on `PATH` by the operating system.
  Future<List<McpEngine>> _engineVersions(
    HeadlessRunResult result,
    CliArgs args,
  ) async {
    final ids = <String>[
      for (final id in result.statuses.keys.toList()..sort())
        if (result.statuses[id]!.phase != EngineRunPhase.unavailable) id,
    ];
    return await Future.wait(<Future<McpEngine>>[
      for (final id in ids)
        () async {
          String? version;
          final engine = registry.get(id);
          if (engine != null) {
            try {
              version = await engine
                  .detectVersion(
                    HeadlessRunner.binaryFor(binaryEngineIdFor(id), args),
                  )
                  .timeout(const Duration(seconds: 10));
            } on Object {
              version = null;
            }
          }
          final v = version?.trim() ?? '';
          return McpEngine(name: id, version: v.isEmpty ? 'unknown' : v);
        }(),
    ]);
  }

  /// Each finding's baseline state, and a warning when the baseline cannot
  /// be read. The gate's own classification when `--fail-on-new-violations`
  /// ran; otherwise the project's baseline (or `--baseline`), read and
  /// classified the same way; `null` for every finding when there is none.
  Future<(LintBaselineState, List<McpDiagnostic>)> _baselineView(
    HeadlessRunResult result,
    CliArgs args,
  ) async {
    final project = result.project!;
    List<Violation> fresh;
    List<Violation> existing;
    if (result.baselinePath != null) {
      if (!result.baselineApplied) {
        return (noBaseline, const <McpDiagnostic>[]);
      }
      fresh = result.newViolations;
      existing = result.persistingViolations;
    } else {
      final path = CliBaselineReader.resolvePath(
        projectRoot: project.rootPath,
        explicitPath: args.baselinePath,
      );
      final read = await const CliBaselineReader().read(path);
      if (read.isCorrupt) {
        return (
          noBaseline,
          <McpDiagnostic>[
            McpDiagnostic.warning(
              'baseline.unreadable',
              'The baseline $path could not be read (${read.error}), so no '
                  'finding is marked new or existing.',
            ),
          ],
        );
      }
      if (!read.hasBaseline) return (noBaseline, const <McpDiagnostic>[]);
      final delta = BaselineFilter.classify(
        current: result.reportableViolations,
        baseline: read.baseline,
        projectRoot: project.rootPath,
      );
      fresh = delta.newViolations;
      existing = delta.persistingViolations;
    }
    final isNew = Set<Violation>.identity()..addAll(fresh);
    final isExisting = Set<Violation>.identity()..addAll(existing);
    return (
      (Violation v) => isNew.contains(v)
          ? 'new'
          : isExisting.contains(v)
          ? 'existing'
          : null,
      const <McpDiagnostic>[],
    );
  }

  // ── rule, waivers ─────────────────────────────────────────────────

  static ArgParser _subcommandParser() => ArgParser()
    ..addFlag(
      CliArgsParser.kJsonFlag,
      negatable: false,
      help: 'Write the JSON document.',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'This text.');

  /// The document `lintcrux <name> <args>` writes with `--json`; the
  /// `rule` and `waivers` tools come through here too.
  Future<McpDocument> subcommandDocument(String name, List<String> args) async {
    final ArgResults parsed;
    try {
      parsed = _subcommandParser().parse(args);
    } on FormatException catch (e) {
      return McpDocument.usage(
        tool: program,
        command: name,
        message: e.message,
      );
    }
    if (parsed.rest.length != 1) {
      return McpDocument.usage(
        tool: program,
        command: name,
        message: name == kRuleCommand
            ? '`rule` takes one rule id, engineId/ruleId.'
            : '`waivers` takes one .lintcrux project.',
      );
    }
    final operand = parsed.rest.single;
    if (name == kRuleCommand) {
      return ruleDocument(
        program: program,
        id: operand,
        engineIds: registry.engineIds,
      );
    }
    return await waiversDocument(
      program: program,
      projectPath: operand,
      // No engine runs here, so only what is withheld from every answer
      // (the managed waivers) can be.
      extra: withheld == null
          ? null
          : (project) => withheld!(project, cdcRan: false),
    );
  }

  Future<int> _subcommand(
    String name,
    List<String> args, {
    required void Function(String line) stdoutSink,
    required void Function(String line) stderrSink,
  }) async {
    if (args.contains('--help') || args.contains('-h')) {
      stdoutSink(
        name == kRuleCommand
            ? 'What a lint rule checks, its default severity and help link.\n\n'
                  'Usage: lintcrux rule <engine>/<rule> [--json]'
            : 'The waivers in force for a project: inline pragmas, Verilator '
                  'configuration files and the baseline. Read only.\n\n'
                  'Usage: lintcrux waivers <project.lintcrux> [--json]',
      );
      stdoutSink(_subcommandParser().usage);
      return CliExitCode.clean;
    }
    final document = await subcommandDocument(name, args);
    if (args.contains('--${CliArgsParser.kJsonFlag}')) {
      _writeDocument(stdoutSink, document);
    } else {
      final body = document.body;
      if (body != null) _describe(name, body).forEach(stdoutSink);
    }
    for (final d in document.diagnostics) {
      stderrSink('lintcrux $name: ${d.severity.name}: ${d.message}');
    }
    return McpExitCodes.suite.exitCodeFor(document.outcome);
  }

  static List<String> _describe(String name, Map<String, Object?> body) {
    if (name == kRuleCommand) {
      return <String>[
        '${body['id']}',
        if (body['default_severity'] != null)
          'default severity: ${body['default_severity']}',
        if (body['help_uri'] != null) 'help: ${body['help_uri']}',
      ];
    }
    final waivers = body['waivers']! as List<Object?>;
    return <String>[
      for (final w in waivers.cast<Map<String, Object?>>())
        <String>[
          w['kind']! as String,
          w['rule']! as String,
          switch (w['scope']) {
            final Map<String, Object?> s => '${s['file']}:${s['line']}',
            _ => '-',
          },
          if (w['pattern'] != null) '${w['pattern']}',
        ].join('  '),
      '${body['total']} waivers',
    ];
  }

  // ── mcp ───────────────────────────────────────────────────────────

  /// The document the `lint` tool returns for [argv] (the tool's argument
  /// vector): the bare command line's own `--json` document.
  ///
  /// A later page of the same call (`offset` above 0, every other argument
  /// the same, and every file the run read unchanged) reuses the run before
  /// it, so paging does not run the engines again.
  Future<McpDocument> lintToolDocument(
    List<String> argv, {
    void Function(String line)? log,
  }) async {
    final parsed = _parse(<String>[...argv, '--${CliArgsParser.kJsonFlag}']);
    if (!parsed.isSuccess) {
      return McpDocument.usage(
        tool: program,
        command: kLintCommand,
        message: parsed.error!,
      );
    }
    var args = parsed.args!;
    final decorate = argsDecorator;
    if (decorate != null) args = decorate(args, log ?? stderr.writeln);
    final key = _pageKey(argv);
    final last = _lastPage;
    _LintRun? run;
    if ((args.offset ?? 0) > 0 && last != null && last.key == key) {
      final project = last.run.result.project;
      final stamps = project == null
          ? null
          : lintInputStamps(project, last.run.result.projectFilePath);
      if (stamps != null && _sameStamps(stamps, last.stamps)) run = last.run;
    }
    if (run == null) {
      run = await _lintRun(args, null);
      final project = run.result.project;
      final stamps = project == null
          ? null
          : lintInputStamps(project, run.result.projectFilePath);
      _lastPage = stamps == null ? null : _LintPage(key, run, stamps);
    }
    return _lintDocument(run, args);
  }

  static String _pageKey(List<String> argv) {
    final kept = <String>[];
    for (var i = 0; i < argv.length; i++) {
      if (argv[i] == '--${CliArgsParser.kLimitOption}' ||
          argv[i] == '--${CliArgsParser.kOffsetOption}') {
        i++;
        continue;
      }
      kept.add(argv[i]);
    }
    return kept.join('\x00');
  }

  static bool _sameStamps(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// The MCP server over `lint`, `rule` and `waivers`, its paths held
  /// inside [root].
  McpServer server({
    required String root,
    McpTelemetry? telemetry,
    void Function(String line)? log,
  }) => McpServer(
    program: program,
    instructions: kLintcruxMcpInstructions,
    tools: kLintcruxMcpTools,
    confinement: Confinement(root),
    telemetry: telemetry,
    log: log,
    runner: (call) async => McpCommandOutput.document(
      call.tool.name == kLintCommand
          ? await lintToolDocument(call.arguments.argv, log: log)
          : await subcommandDocument(call.tool.command, <String>[
              ...call.arguments.argv,
              '--${CliArgsParser.kJsonFlag}',
            ]),
    ),
  );

  Future<int> _serve(
    List<String> args, {
    required void Function(String line) stdoutSink,
    required void Function(String line) stderrSink,
    Stream<List<int>>? input,
    StreamSink<List<int>>? output,
  }) async {
    final parser = ArgParser()
      ..addOption(
        'root',
        help: 'Every path a tool receives must be inside it.',
        valueHelp: 'dir',
        defaultsTo: Directory.current.path,
      )
      ..addOption(
        'license-file',
        valueHelp: 'path',
        help:
            'A licence file for the tools that need one. The three tools of '
            'this binary are free and read none.',
      )
      ..addFlag('help', abbr: 'h', negatable: false, help: 'This text.');
    final ArgResults parsed;
    try {
      parsed = parser.parse(args);
    } on FormatException catch (e) {
      stderrSink('lintcrux mcp: ${e.message}');
      stderrSink(parser.usage);
      return CliExitCode.usage;
    }
    if (parsed.flag('help')) {
      stdoutSink(
        'Serve lint, rule and waivers as MCP tools: newline-delimited '
        'JSON-RPC on stdin and stdout.\n\n'
        'Usage: lintcrux mcp [--root <dir>] [--license-file <path>]',
      );
      stdoutSink(parser.usage);
      return CliExitCode.clean;
    }
    if (parsed.rest.isNotEmpty) {
      stderrSink('lintcrux mcp: unexpected `${parsed.rest.first}`');
      return CliExitCode.usage;
    }
    final server = this.server(
      root: parsed.option('root')!,
      telemetry: _mcpTelemetry(),
      log: stderrSink,
    );
    final problem = server.confinement.rootProblem();
    if (problem != null) {
      stderrSink('lintcrux mcp: $problem');
      return CliExitCode.usage;
    }
    // A signal reaps the engines a call started, as it does for a run.
    return await signalGuard.run(stderrSink: stderrSink, () async {
      await server.serve(input ?? stdin, output ?? stdout);
      return CliExitCode.clean;
    });
  }
}

/// A lint run and what its `--json` document needs beyond it.
class _LintRun {
  _LintRun(
    this.result, {
    this.engines = const <McpEngine>[],
    this.design,
    this.baseline = noBaseline,
    this.extra = const <McpDiagnostic>[],
  });

  final HeadlessRunResult result;
  final List<McpEngine> engines;
  final McpDesignFingerprint? design;
  final LintBaselineState baseline;
  final List<McpDiagnostic> extra;
}

/// The `mcp` server's last lint run, by its argument vector without the
/// page, and the state of the files it read.
class _LintPage {
  _LintPage(this.key, this.run, this.stamps);

  final String key;
  final _LintRun run;
  final List<String> stamps;
}
