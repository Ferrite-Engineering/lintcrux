// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The three tools of `lintcrux mcp`, and what the server checks before it
/// lets one run.
///
/// Each tool's fields make both its `inputSchema` and the command line it
/// runs (`crux_mcp`'s `McpTool`), and the server runs that command line's
/// own code in process (`LintcruxCli`), so a tool's text is byte for byte
/// what `lintcrux ... --json` writes. Not offered, in any form: an engine
/// path override (it would run a binary the caller names), an export or a
/// baseline (they write), `--allow-missing-engines` (it weakens the gate),
/// and a project's raw engine flags (`extraOptions`), which can name a file
/// the check cannot see.
library;

import 'dart:io';

import 'package:crux_mcp/crux_mcp.dart';
import 'package:lintcrux/core/app_info/build_info.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/headless/lint_document.dart';
import 'package:lintcrux/headless/rule_command.dart';
import 'package:lintcrux/headless/waivers_command.dart';
import 'package:lintcrux/services/engines/engine_run_context.dart'
    show kExtraOptionsKey;
import 'package:lintcrux/services/engines/yosys/yosys_engine_support.dart'
    show kYosysWorkingDirectoryOption;
import 'package:lintcrux/services/headless/cli_baseline_reader.dart';
import 'package:lintcrux/services/headless/headless_input_resolver.dart';
import 'package:lintcrux/services/project/project_file_service.dart';
import 'package:lintcrux/services/rohd/rohd_source_loader.dart'
    show kRohdOptionsKey, kRohdSidecarOption;
import 'package:path/path.dart' as p;

/// The `instructions` paragraph `initialize` returns. The full text is
/// `docs/agent/LINTCRUX.md`.
const String kLintcruxMcpInstructions =
    'LintCrux lints Verilog, SystemVerilog and VHDL with the engines a '
    'project configures. Call lint with a .lintcrux project, or with source '
    'files, for every finding with its rule, severity and file:line. A run '
    'in which an engine failed, timed out or was missing has the outcome '
    "engine_error and is never a clean result. Call rule for a rule's "
    'default severity and help link, and waivers for the waivers in force. '
    'Cite each finding as file:line. Waivers and baselines are a '
    "person's decision: never edit one to make a run clean.";

/// The `lint` tool: the bare `lintcrux` command line with `--json`.
final McpTool kLintTool = McpTool(
  name: kLintCommand,
  description:
      'Lint a design with its configured engines (Verilator, Verible, Slang, '
      'Yosys, GHDL, svlint, CDC). Returns findings with rule, severity and '
      'file:line. A failed or missing engine fails the run; it is never '
      'reported clean.',
  fields: const <McpField>[
    McpField(
      'project',
      kind: McpFieldKind.path,
      description: 'A .lintcrux project; or give files.',
    ),
    McpField('files', kind: McpFieldKind.path, many: true),
    McpField('top', kind: McpFieldKind.text, flag: '--top'),
    McpField(
      'engines',
      kind: McpFieldKind.text,
      flag: '--engine',
      many: true,
    ),
    McpField(
      'params',
      kind: McpFieldKind.text,
      flag: '--param',
      many: true,
      description: 'NAME=VALUE',
    ),
    McpField(
      'new_only',
      kind: McpFieldKind.boolean,
      flag: '--fail-on-new-violations',
      description: 'Fail the gate on findings absent from the baseline.',
    ),
    McpField(
      'limit',
      kind: McpFieldKind.integer,
      flag: '--limit',
      description: 'Default 100, at most 1000.',
    ),
    McpField('offset', kind: McpFieldKind.integer, flag: '--offset'),
  ],
  checkNamedFiles: checkProjectFiles,
);

/// The `rule` tool: `lintcrux rule <id> --json`.
final McpTool kRuleTool = McpTool(
  name: kRuleCommand,
  description:
      "A lint rule's default severity and help link, by the engineId/ruleId "
      'a finding gives.',
  fields: const <McpField>[McpField('id', kind: McpFieldKind.text)],
  required: const <String>['id'],
);

/// The `waivers` tool: `lintcrux waivers <project> --json`.
final McpTool kWaiversTool = McpTool(
  name: kWaiversCommand,
  description:
      'The waivers in force for a project: rule, scope, reason, author and '
      "expiry. Read only; a waiver is a person's decision.",
  fields: const <McpField>[McpField('project', kind: McpFieldKind.path)],
  required: const <String>['project'],
  checkNamedFiles: checkProjectFiles,
);

/// The tools the open-core server lists, in order.
final List<McpTool> kLintcruxMcpTools = <McpTool>[
  kLintTool,
  kRuleTool,
  kWaiversTool,
];

/// The `mcp.tool_call` counter of the open-core binary: sent only under the
/// consent the LintCrux desktop app recorded on this machine, and never
/// when the `CI` environment variable is set.
McpTelemetry lintcruxMcpTelemetry() => McpTelemetry.desktop(
  HeadlessTelemetry(
    product: CruxTelemetryProduct.lintcrux,
    pro: false,
    appVersion: LintCruxBuildInfo.productVersion,
  ),
);

/// The `named-files` check of `lint` and `waivers`: the `.lintcrux` the call
/// names is read the way the command will read it, and every file and
/// directory it names must be inside the root.
///
/// A project that cannot be read is left to the command, which says why in
/// its own document; nothing it names is opened first. A project that hands
/// an engine raw flags (`perEngineOptions.<engine>.extraOptions`) is
/// refused: a flag can name a file, and the check cannot read flags the way
/// each engine does.
Future<RefusedPath?> checkProjectFiles(
  McpArguments arguments,
  Confinement confinement,
) async {
  final projectPath = arguments.values['project'];
  if (projectPath is! String) return null;
  if (p.extension(projectPath).toLowerCase() !=
      HeadlessInputResolver.projectExtension) {
    return null;
  }
  if (!File(projectPath).existsSync()) return null;
  final LintProject project;
  try {
    project = HeadlessInputResolver.absolutized(
      await const ProjectFileService().read(projectPath),
      projectPath,
    );
  } on Object {
    return null;
  }
  for (final entry in project.perEngineOptions.entries) {
    final extra = entry.value[kExtraOptionsKey];
    if (extra is List && extra.isNotEmpty) {
      return RefusedPath(
        projectPath,
        '`$projectPath` passes raw flags to ${entry.key} '
        '(perEngineOptions.${entry.key}.$kExtraOptionsKey), which the server '
        'does not run, since a flag can name a file outside the root. Run '
        'lintcrux on this project from the command line.',
      );
    }
  }
  return confinement.confineAll(projectNamedPaths(project));
}

/// Every file and directory [project] (absolutized) names, absolute: its
/// root, sources, include directories, constraint files, the Verilator
/// configuration files, and the per-engine options that name a path
/// (`configPath`, `workingDirectory`, the ROHD sidecars).
List<String> projectNamedPaths(LintProject project) {
  final root = project.rootPath;
  String against(String entry) =>
      p.normalize(p.isAbsolute(entry) ? entry : p.join(root, entry));
  final optionPaths = <String>[
    for (final options in project.perEngineOptions.values) ...<String>[
      if (options['configPath'] case final String s when s.isNotEmpty)
        against(s),
      if (options[kYosysWorkingDirectoryOption] case final String s
          when s.isNotEmpty)
        against(s),
    ],
    ...switch (project.perEngineOptions[kRohdOptionsKey]?[kRohdSidecarOption]) {
      final String s when s.isNotEmpty => <String>[against(s)],
      final List<Object?> l => <String>[
        for (final s in l)
          if (s is String && s.isNotEmpty) against(s),
      ],
      _ => const <String>[],
    },
  ];
  return <String>[
    root,
    ...project.sourceFiles,
    ...project.includePaths,
    ...project.constraintFiles,
    ...verilatorWaiverFiles(project),
    ...optionPaths,
  ];
}

/// The most entries [lintInputStamps] reads before it gives up, so a page
/// request never walks a whole disk.
const int kLintStampLimit = 5000;

/// The state of everything a lint run of [project] read, as `path`,
/// length and modification time, for the server's page cache: a later page
/// reuses a run only when this is unchanged. `null` when it cannot be told
/// (too many files, a directory that cannot be listed), which means "run
/// again".
List<String>? lintInputStamps(LintProject project, String? projectFile) {
  final stamps = <String>[];
  void stamp(String path) {
    final stat = FileStat.statSync(path);
    stamps.add(
      stat.type == FileSystemEntityType.notFound
          ? '$path\x00-'
          : '$path\x00${stat.type}\x00${stat.size}\x00'
                '${stat.modified.microsecondsSinceEpoch}',
    );
  }

  try {
    <String>{
      ?projectFile,
      ...projectNamedPaths(project),
      CliBaselineReader.resolvePath(projectRoot: project.rootPath),
    }.forEach(stamp);
    // Files a run reads without the project naming them: engine
    // configuration in the root, `cdc.yaml` and ROHD sidecars beside the
    // sources, and whatever an include directory holds.
    final flat = <String>{
      project.rootPath,
      for (final f in project.sourceFiles) p.dirname(f),
    };
    for (final dir in flat) {
      if (!Directory(dir).existsSync()) continue;
      for (final e in Directory(dir).listSync(followLinks: false)) {
        stamp(e.path);
        if (stamps.length > kLintStampLimit) return null;
      }
    }
    for (final dir in project.includePaths) {
      if (!Directory(dir).existsSync()) continue;
      for (final e in Directory(dir).listSync(recursive: true)) {
        stamp(e.path);
        if (stamps.length > kLintStampLimit) return null;
      }
    }
  } on FileSystemException {
    return null;
  }
  return stamps..sort();
}
