// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:args/args.dart';
import 'package:lintcrux/core/cli/cli_args.dart';

/// Parses LintCrux CLI arguments into a [CliArgs] snapshot.
///
/// Backed by `package:args` so behavior matches the broader Dart CLI
/// ecosystem (`pub`, `flutter`, `melos`). The parser is total: it
/// either returns a [CliArgsParseResult] with the parsed [CliArgs] or
/// a usage error wrapping the human-readable error message produced
/// by `args`.
class CliArgsParser {
  /// Creates a parser. Stateless — safe to construct as `const` and
  /// reuse across invocations.
  CliArgsParser() : _parser = _buildParser();

  final ArgParser _parser;

  /// Parses [args] and returns a [CliArgsParseResult]. On parser
  /// failure (unknown flag, missing value), `error` is non-null and
  /// `args` is `null`; callers should print `usage` plus the error and
  /// exit non-zero. On success, `args` is non-null and `error` is `null`.
  CliArgsParseResult parse(List<String> args) {
    final ArgResults results;
    try {
      results = _parser.parse(args);
    } on FormatException catch (e) {
      return CliArgsParseResult(error: e.message, usage: usage);
    }

    final binaryPaths = <String, String>{};
    for (final engineId in binaryPathEngineIds) {
      final v = results['$engineId-path'] as String?;
      if (v != null && v.isNotEmpty) {
        binaryPaths[engineId] = v;
      }
    }

    // `--sarif <path>` is the shorthand for `--export sarif --out <path>`.
    // Normalize it here so every downstream consumer reads one pair of
    // fields instead of branching on which spelling the user typed.
    final sarifShorthand = results['sarif'] as String?;
    var exportFormat = results['export'] as String?;
    var exportOut = results['out'] as String?;
    if (sarifShorthand != null && sarifShorthand.isNotEmpty) {
      exportFormat ??= kSarifExportFormat;
      exportOut ??= sarifShorthand;
    }

    // An `--export` with no destination, or an `--out` with no format,
    // is a usage error rather than a silently-skipped export: a CI step
    // that meant to produce an upload artifact and produced nothing must
    // fail loudly, not pass.
    if (exportFormat != null && (exportOut == null || exportOut.isEmpty)) {
      return CliArgsParseResult(
        error:
            'Option "--export $exportFormat" requires "--out <path>" '
            '(or use the "--sarif <path>" shorthand).',
        usage: usage,
      );
    }
    if (exportOut != null && exportFormat == null) {
      return CliArgsParseResult(
        error: 'Option "--out" requires "--export <format>".',
        usage: usage,
      );
    }
    if (exportFormat != null && !kExportFormats.contains(exportFormat)) {
      return CliArgsParseResult(
        error:
            'Unknown export format "$exportFormat". '
            'Expected one of: ${kExportFormats.join(', ')}.',
        usage: usage,
      );
    }

    final parsed = CliArgs(
      paths: List<String>.unmodifiable(results.rest),
      configPath: results['config'] as String?,
      sarifOutputPath: exportFormat == kSarifExportFormat ? exportOut : null,
      sessionPath: results['session'] as String?,
      workspacePath: results['workspace'] as String?,
      exitCodeOnFindings: results['exit-code'] as bool? ?? false,
      showHelp: results['help'] as bool? ?? false,
      showVersion: results['version'] as bool? ?? false,
      importFilelistPath: results['import-filelist'] as String?,
      importEdamPath: results['import-edam'] as String?,
      engineBinaryPaths: Map<String, String>.unmodifiable(binaryPaths),
      topModule: results['top'] as String?,
      exportFormat: exportFormat,
      exportOutputPath: exportOut,
      baselinePath: results['baseline'] as String?,
      failOnNewViolations: results['fail-on-new-violations'] as bool? ?? false,
      allowMissingEngines: results['allow-missing-engines'] as bool? ?? false,
      engineIds: List<String>.unmodifiable(
        (results['engine'] as List<String>?) ?? const <String>[],
      ),
      quiet: results['quiet'] as bool? ?? false,
    );
    return CliArgsParseResult(args: parsed, usage: usage);
  }

  /// The `--export` value that selects SARIF 2.1.0 output.
  static const String kSarifExportFormat = 'sarif';

  /// Every value `--export <format>` accepts. Matches the four formats
  /// `ViolationExporters` can emit; keep the two in sync.
  static const List<String> kExportFormats = <String>[
    kSarifExportFormat,
    'json',
    'csv',
    'html',
  ];

  /// Engines that accept a `--<engineId>-path` CLI override: every engine
  /// in `defaultEngineRegistry()` that starts a binary of its own. CDC is
  /// absent because it runs Yosys and reads `--yosys-path` (see
  /// `binaryEngineIdFor`).
  static const List<String> binaryPathEngineIds = <String>[
    'verilator',
    'verible',
    'slang',
    'ghdl',
    'svlint',
    'yosys',
  ];

  /// Multi-line usage block. Callers print this for `--help` and on
  /// parse error. Wrapped at 76 columns to match Dart-tool conventions.
  String get usage =>
      '''
Usage: lintcrux [options] [path...]

Aggregate Verilog/SystemVerilog/VHDL lint output across multiple
engines and surface every warning in a single dashboard.

The `lintcrux` executable built from bin/lintcrux.dart runs headless:
it loads the project, runs the enabled engines, applies waivers and the
baseline, writes the requested export, and exits with a meaningful code.
No window is opened. The desktop app shares this argument parser.

Positional arguments:
  path                  One or more files to lint. May be:
                          - a .lintcrux project file, or
                          - one or more .v / .sv / .vhd / .vhdl
                            source files forming an ad-hoc project.
                        A positional that is neither is reported as an
                        error and exits 64 — never silently ignored.

${_parser.usage}
Exit codes:
   0  clean — nothing to report, or findings present but no gate asked for
   1  violations — --exit-code was passed and findings remain
   2  new violations — --fail-on-new-violations was passed and a finding
      is absent from the baseline
   3  run failed — an engine failed, timed out, or was unavailable; the
      named project could not be loaded (unparseable, no sources, or a
      listed source missing); or the export could not be written
   4  over threshold — the organization's signed ciGateThreshold was
      exceeded. There is no flag for it: it comes from .crux-policy.json
  64  usage error — bad flag, an unusable positional argument, or a
      path that does not exist
  65  data error — --import-filelist / --import-edam could not
      convert the input file

Examples:
  lintcrux project.lintcrux
  lintcrux foo.v bar.sv --top top_module --engine verilator
  lintcrux project.lintcrux --export sarif --out lint.sarif --exit-code
  lintcrux project.lintcrux --fail-on-new-violations
  lintcrux project.lintcrux --config ci-overrides.lintcrux --exit-code
''';

  static ArgParser _buildParser() {
    final parser = ArgParser();
    for (final id in binaryPathEngineIds) {
      parser.addOption(
        '$id-path',
        valueHelp: 'path',
        help:
            'Override the $id binary location for this run only. '
            'Equivalent to setting Custom in Settings → Engines but '
            'scoped to a single invocation. Honored by CI scripts.'
            '${id == 'yosys' ? ' Also the binary the cdc engine runs.' : ''}',
      );
    }
    return parser
      ..addOption(
        'config',
        abbr: 'c',
        valueHelp: 'path',
        help:
            'Overlay a partial .lintcrux document (JSON) on top of the '
            'loaded project. Only the keys present in the overlay are '
            'replaced. Useful for per-CI tuning without editing the '
            'project file in-tree.',
      )
      ..addOption(
        'top',
        valueHelp: 'module',
        help:
            'Top module / entity name. Required by some engines for '
            'elaboration ordering. Sets the top module for an ad-hoc '
            'positional source-file run, and overrides the project '
            "file's topModule when one is loaded.",
      )
      ..addMultiOption(
        'engine',
        valueHelp: 'id',
        help:
            'Run only this engine (repeatable). One of verilator, '
            'verible, slang, yosys, ghdl, svlint, cdc. Overrides the '
            "project's enabledEngineIds for this invocation — the "
            'usual shape for a CI image that only installs one engine.',
      )
      ..addOption(
        'export',
        valueHelp: 'format',
        allowed: kExportFormats,
        help:
            'Write the aggregated violation set in this format to the '
            '--out path. Requires --out.',
      )
      ..addOption(
        'out',
        abbr: 'o',
        valueHelp: 'path',
        help: 'Destination file for --export. Requires --export.',
      )
      ..addOption(
        'sarif',
        valueHelp: 'out.sarif',
        help:
            'Shorthand for "--export sarif --out <path>". Writes the '
            'aggregated violation set as SARIF 2.1.0, suitable for '
            'upload to GitHub Code Scanning or GitLab SAST.',
      )
      ..addOption(
        'baseline',
        valueHelp: 'path',
        help:
            'Baseline file consulted by --fail-on-new-violations. '
            'Defaults to .lintcrux-baseline.json in the project root. '
            'Baselines are written by LintCrux Pro; the CLI reads them.',
      )
      ..addOption(
        'session',
        valueHelp: 'session.lintcrux-session',
        help:
            'Apply UI state from this .lintcrux-session file after '
            'opening the project (selection, filters, sort).',
      )
      ..addOption(
        'workspace',
        valueHelp: 'name.lintcrux-workspace',
        help:
            'Open the named workspace on launch, replacing the '
            'auto-saved workspace document. Any positional .lintcrux '
            'paths still open as additional tabs in the loaded '
            'workspace.',
      )
      ..addFlag(
        'exit-code',
        negatable: false,
        help:
            'Exit 1 when any non-suppressed violation is present at '
            'end of run. Use to gate CI on lint clean.',
      )
      ..addFlag(
        'fail-on-new-violations',
        negatable: false,
        help:
            'Exit 2 when a violation is present that the baseline does '
            'not contain. Pre-existing findings do not fail the build. '
            'Composes with --exit-code.',
      )
      ..addFlag(
        'allow-missing-engines',
        negatable: false,
        help:
            'Treat an engine whose binary cannot be found as skipped '
            'rather than as a run failure. Off by default: a CI job '
            'that asked for an engine and silently ran none is a false '
            'clean result.',
      )
      ..addFlag(
        'quiet',
        abbr: 'q',
        negatable: false,
        help:
            'Suppress the per-violation listing; print only the summary '
            'line and any diagnostics. Exit codes are unaffected.',
      )
      ..addOption(
        'import-filelist',
        valueHelp: 'rtl.f',
        help:
            'Import a Vivado-style `.f` filelist into a new '
            '`.lintcrux` project beside the input. Recursive `-f` '
            'includes, `+incdir+`, `+define+`, and env-variable '
            'expansion are honored. The new project is opened on '
            'launch unless `--help` / `--version` is also present.',
      )
      ..addOption(
        'import-edam',
        valueHelp: 'design.eda.yml',
        help:
            'Import a FuseSoC/Edalize EDAM file into a new `.lintcrux` '
            'project beside the input. Sources, include dirs, defines, '
            'toplevel, per-file language, Verilator options, and `.vlt` '
            'waivers are honored; per-file core provenance is recorded. '
            'Generate the EDAM with `fusesoc run --target=lint --setup '
            '<core>`. The new project is opened on launch (GUI) or '
            'linted (headless).',
      )
      ..addFlag(
        'reset-telemetry-consent',
        negatable: false,
        help:
            "Testing aid. Forget this installation's telemetry answer so "
            'the one-time first-launch disclosure appears again. The '
            'installation ID is kept. Acted on during GUI bootstrap; the '
            'headless runner accepts and ignores it. The dialog only appears '
            'at all on a build where telemetry is live '
            '(--dart-define=TELEMETRY_DEV=true, or BETA_PERIOD=false).',
      )
      ..addFlag(
        'reset-eula',
        negatable: false,
        help:
            "Testing aid. Forget this installation's acceptance of the "
            'End User License Agreement so it is presented again on this '
            'launch. Acted on during GUI bootstrap; the headless runner '
            'accepts and ignores it.',
      )
      ..addFlag(
        'help',
        abbr: 'h',
        negatable: false,
        help: 'Print this usage block and exit.',
      )
      ..addFlag(
        'version',
        negatable: false,
        help: 'Print the LintCrux version string and exit.',
      );
  }
}

/// Result of [CliArgsParser.parse].
///
/// Either [args] (success) or [error] (parse failure) is non-null;
/// [usage] is always populated so the caller can print a helpful
/// usage block on either path.
class CliArgsParseResult {
  /// Creates a parse result. Pass [args] on success or [error] on
  /// failure; [usage] is required either way.
  const CliArgsParseResult({
    required this.usage,
    this.args,
    this.error,
  }) : assert(
         (args != null) ^ (error != null),
         'exactly one of args / error must be non-null',
       );

  /// The successfully parsed arguments, or `null` on parse failure.
  final CliArgs? args;

  /// A human-readable error message produced by the underlying
  /// `package:args` parser. Suitable for printing to stderr verbatim.
  final String? error;

  /// The CLI usage block. Always populated; callers print it for
  /// `--help`, on parse error, and from `?` triggers in the future.
  final String usage;

  /// `true` when the parser succeeded.
  bool get isSuccess => args != null;
}
