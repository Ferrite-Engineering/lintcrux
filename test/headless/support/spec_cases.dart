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
    hostOutsidePaths(
          json['arguments'],
          specOutsidePrefix(Directory.systemTemp.path),
        )!
        as Map<String, Object?>,
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

/// [text], a JSON document the tool wrote, with [root] written as the goldens
/// write it ([goldenRoot], and `/` between every path's segments).
///
/// On a POSIX host the root appears verbatim. On Windows it is `C:\...`, which
/// JSON writes as `C:\\...`, and every path under it joins with `\`, so the
/// goldens' `/spec/fixtures/lint/a.sv` reads `C:\\Users\\...\\lint\\a.sv`
/// there; the same file, spelled by the host. [windows] says which spelling
/// to undo (the host's by default); it is a parameter so a test can prove the
/// Windows case on any machine.
String normalizeSpecRoot(
  String text, {
  required String root,
  required String goldenRoot,
  bool? windows,
}) {
  final onWindows = windows ?? Platform.isWindows;
  if (!onWindows) {
    return text.replaceAll(root, goldenRoot);
  }
  final escaped = root.replaceAll(r'\', r'\\');
  return text
      .replaceAll(escaped, goldenRoot)
      .replaceAll(root.replaceAll(r'\', '/'), goldenRoot)
      .replaceAll(r'\\', '/')
      .replaceAll(
        '${specOutsidePrefix(root, windows: true)}$kSpecOutsideDir',
        kSpecOutsideDir,
      );
}

/// The directory the goldens name for a path that is outside the root and
/// exists nowhere: absolute on a POSIX host, but not on Windows, where an
/// absolute path has a drive.
const String kSpecOutsideDir = '/nonexistent-lintcrux-spec';

/// What goes before [kSpecOutsideDir] so the path is absolute on the host
/// whose temporary [root] is given: nothing on POSIX, the root's drive (`C:`)
/// on Windows. The path stays outside the root and is still refused as such,
/// never as "not absolute". [windows] is a parameter so a test can prove the
/// Windows case on any machine.
String specOutsidePrefix(String root, {bool? windows}) {
  if (!(windows ?? Platform.isWindows)) return '';
  final prefix = p.windows.rootPrefix(root);
  return prefix.replaceAll(RegExp(r'[\\/]+$'), '');
}

/// [value] (a string, or a list or map holding strings) with every path that
/// starts with [kSpecOutsideDir] made absolute on the host by [prefix].
Object? hostOutsidePaths(Object? value, String prefix) {
  if (prefix.isEmpty) return value;
  return switch (value) {
    final String s when s.startsWith(kSpecOutsideDir) => '$prefix$s',
    final List<Object?> l => <Object?>[
      for (final e in l) hostOutsidePaths(e, prefix),
    ],
    final Map<String, Object?> m => <String, Object?>{
      for (final e in m.entries) e.key: hostOutsidePaths(e.value, prefix),
    },
    _ => value,
  };
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
    // A path the fixtures name outside the root is spelled for this host
    // (`C:/nonexistent-lintcrux-spec/...` on Windows), so the server judges
    // it outside the root, as on POSIX, and not "not an absolute path".
    final outside = specOutsidePrefix(copy.path);
    for (final e in fixtures.listSync(recursive: true)) {
      if (e is! File) continue;
      final target = File(
        p.join(copy.path, p.relative(e.path, from: fixtures.path)),
      )..createSync(recursive: true);
      if (outside.isNotEmpty && e.path.endsWith('.lintcrux')) {
        target.writeAsStringSync(
          e.readAsStringSync().replaceAll(
            '"$kSpecOutsideDir',
            '"$outside$kSpecOutsideDir',
          ),
        );
      } else {
        target.writeAsBytesSync(e.readAsBytesSync());
      }
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
  String normalize(String text) =>
      normalizeSpecRoot(text, root: root, goldenRoot: goldenRoot);

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
