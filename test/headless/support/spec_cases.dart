// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The cases of `spec/mcp/cases.json`, run through either door: the
/// `lintcrux ... --json` command line and the `lintcrux mcp` tool of the
/// same name.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_mcp/crux_mcp.dart' hide HeadlessTelemetry;
import 'package:lintcrux/core/cli/lintcrux_cli.dart';
import 'package:lintcrux/headless/lint_document.dart';
import 'package:lintcrux/headless/lintcrux_mcp.dart';
import 'package:lintcrux/services/engines/default_engine_registry.dart';
import 'package:path/path.dart' as p;

import 'spec_engines.dart';

/// One case: a tool, its MCP arguments, and its golden document.
class SpecCase {
  SpecCase._(
    this.golden,
    this.tool,
    this.arguments,
    this.door,
    this.engines,
    this.exit,
  );

  factory SpecCase._fromJson(Map<String, Object?> json) => SpecCase._(
    json['golden']! as String,
    json['tool']! as String,
    json['arguments']! as Map<String, Object?>,
    json['door'] as String? ?? 'both',
    SpecScenario.named(json['engines'] as String? ?? 'ok'),
    json['exit'] as int?,
  );

  /// The golden's path under `spec/mcp/goldens/`.
  final String golden;

  /// The tool, which is also the command.
  final String tool;

  /// The `tools/call` arguments; paths are relative to the root.
  final Map<String, Object?> arguments;

  /// `both` when the command line can be given the same arguments; `mcp`
  /// when only the server answers (its own argument and confinement checks).
  final String door;

  /// How the spec's engines end.
  final SpecScenario engines;

  /// The command line's exit code, from the contracts' table: LintCrux's
  /// own codes for `lint`, the suite's for `rule` and `waivers`. `null` for
  /// a case only the server answers.
  final int? exit;

  @override
  String toString() => golden;
}

/// `spec/mcp/cases.json`, read from the package root.
class SpecCases {
  SpecCases._(
    this._copy,
    this.root,
    this.goldenRoot,
    this.goldenVersion,
    this.cases,
  );

  /// Loads the cases, over a copy of the fixtures in a temporary directory
  /// with `spec/mcp/runtime/`'s files installed under the names LintCrux
  /// reads (`installs`): the repository never commits a
  /// `.lintcrux-baseline.json` or `.lintcrux-waivers.json` (`.gitignore`),
  /// and a copy keeps every test file off the committed tree. Call
  /// [dispose] when done.
  factory SpecCases.load() {
    final json =
        jsonDecode(File('spec/mcp/cases.json').readAsStringSync())
            as Map<String, Object?>;
    final copy = Directory.systemTemp.createTempSync('lintcrux_spec_');
    final fixtures = Directory(json['root']! as String);
    for (final e in fixtures.listSync(recursive: true)) {
      if (e is! File) continue;
      File(p.join(copy.path, p.relative(e.path, from: fixtures.path)))
        ..createSync(recursive: true)
        ..writeAsBytesSync(e.readAsBytesSync());
    }
    final installs = json['installs']! as Map<String, Object?>;
    for (final entry in installs.entries) {
      File(p.join(copy.path, entry.key))
        ..createSync(recursive: true)
        ..writeAsBytesSync(
          File(entry.value! as String).readAsBytesSync(),
        );
    }
    return SpecCases._(
      copy,
      copy.path,
      json['golden_root']! as String,
      json['golden_version']! as String,
      <SpecCase>[
        for (final c in json['cases']! as List<Object?>)
          SpecCase._fromJson(c! as Map<String, Object?>),
      ],
    );
  }

  final Directory _copy;

  /// Removes the copy of the fixtures.
  void dispose() {
    if (_copy.existsSync()) _copy.deleteSync(recursive: true);
  }

  /// The server's root: the copy of the fixtures, absolute on this machine.
  final String root;

  /// What the root reads as in a golden.
  final String goldenRoot;

  /// The program version a golden names.
  final String goldenVersion;

  /// Every case.
  final List<SpecCase> cases;

  /// [text] with this machine's root written as the goldens write it.
  String normalize(String text) => text.replaceAll(root, goldenRoot);

  /// The golden document of [c], as written.
  String golden(SpecCase c) =>
      File(p.join('spec', 'mcp', 'goldens', c.golden)).readAsStringSync();

  /// A command line for [c], as the open-core binary builds it, over the
  /// spec's engines for `lint` and the real registry otherwise.
  LintcruxCli cli(SpecCase c, {McpProgram? program}) => LintcruxCli(
    registry: c.tool == kLintCommand
        ? specRegistry(c.engines)
        : defaultEngineRegistry(),
    installSignalReaper: false,
    program:
        program ??
        McpProgram(name: kLintcruxProgramName, version: goldenVersion),
    withheld: openCoreWithheld,
    mcpTelemetry: () => null,
  );

  /// What the `lintcrux mcp` tool answers for [c]: the decoded tool result.
  Future<Map<String, Object?>> callTool(LintcruxCli cli, SpecCase c) async {
    final server = cli.server(root: root);
    final line = await server.handleLine(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': <String, Object?>{'name': c.tool, 'arguments': c.arguments},
      }),
    );
    final reply = jsonDecode(line!) as Map<String, Object?>;
    return reply['result']! as Map<String, Object?>;
  }

  /// The command line [c]'s arguments become, as the server builds it.
  List<String> argv(SpecCase c) {
    final tool = kLintcruxMcpTools.firstWhere((t) => t.name == c.tool);
    final checked = tool.check(c.arguments, Confinement(root));
    if (checked is! McpArguments) {
      throw StateError('$c: the arguments are refused; use door "mcp"');
    }
    return <String>[
      if (tool.name != kLintCommand) tool.command,
      ...checked.argv,
      '--json',
    ];
  }

  /// What `lintcrux <argv>` writes on stdout, and its exit code.
  Future<(String, int)> runCommandLine(
    LintcruxCli cli,
    List<String> argv,
  ) async {
    final out = <String>[];
    final code = await cli.run(
      argv,
      stdoutSink: out.add,
      stderrSink: (_) {},
    );
    return (out.isEmpty ? '' : '${out.join('\n')}\n', code);
  }
}
