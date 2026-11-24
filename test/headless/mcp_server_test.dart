// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// `lintcrux mcp`: its definitions and their budget, the protocol through a
// scripted client, path confinement (refused paths are never run or read),
// paging without re-running the engines, and the tool-call counter.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_mcp/crux_mcp.dart' hide HeadlessTelemetry;
import 'package:crux_mcp/crux_mcp_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/cli/lintcrux_cli.dart';
import 'package:lintcrux/headless/lint_document.dart';
import 'package:lintcrux/headless/lintcrux_mcp.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:path/path.dart' as p;

import 'support/spec_engines.dart';

void main() {
  late Directory tmp;
  late String root;
  late EngineRegistry registry;
  late LintcruxCli cli;

  /// A copy of `spec/fixtures/design` under the root, so a test may edit it.
  void copyDesign() {
    final from = Directory(p.join('spec', 'fixtures', 'design'));
    for (final e in from.listSync(recursive: true)) {
      if (e is! File) continue;
      final rel = p.relative(e.path, from: from.path);
      File(p.join(root, 'design', rel))
        ..createSync(recursive: true)
        ..writeAsBytesSync(e.readAsBytesSync());
    }
  }

  SpecEngine engine(String id) => registry.get(id)! as SpecEngine;

  Future<Map<String, Object?>> call(
    String tool,
    Map<String, Object?> arguments, {
    McpServer? server,
  }) async {
    final line = await (server ?? cli.server(root: root)).handleLine(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': <String, Object?>{'name': tool, 'arguments': arguments},
      }),
    );
    final result =
        (jsonDecode(line!) as Map<String, Object?>)['result']!
            as Map<String, Object?>;
    return jsonDecode(
          ((result['content']! as List<Object?>).single!
                  as Map<String, Object?>)['text']!
              as String,
        )
        as Map<String, Object?>;
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lintcrux_mcp_');
    root = p.join(tmp.path, 'root');
    Directory(root).createSync();
    copyDesign();
    registry = specRegistry(SpecScenario.ok);
    cli = LintcruxCli(
      registry: registry,
      installSignalReaper: false,
      withheld: openCoreWithheld,
      mcpTelemetry: () => null,
    );
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('definitions', () {
    test("are the contracts' definitions, generated from one table", () {
      // `spec/mcp/definitions.json` holds the definitions of mcp-tool-contracts
      // sections 5.1 to 5.3 as written there, member order included.
      final contract =
          jsonDecode(
                File(
                  p.join('spec', 'mcp', 'definitions.json'),
                ).readAsStringSync(),
              )
              as List<Object?>;
      expect(
        <String>[
          for (final t in kLintcruxMcpTools) mcpRenderJsonLine(t.definition()),
        ],
        <String>[for (final d in contract) mcpRenderJsonLine(d)],
      );
    });

    test('stay inside the budget, and the budget test fails when crossed', () {
      final server = cli.server(root: root);
      expectDefinitionBudget(server);
      // Contracts 7 measured lint at 789 characters and the server at 1,825
      // with its instructions at their 600 ceiling.
      expect(
        kLintcruxMcpTools
            .map((t) => t.definitionLength)
            .reduce(
              (a, b) => a > b ? a : b,
            ),
        lessThan(800),
      );
      expect(mcpServerDefinitionLength(server), lessThan(1900));
      expect(
        () => expectDefinitionBudget(server, perTool: 500),
        throwsA(isA<McpBudgetExceeded>()),
      );
      expect(
        () => expectDefinitionBudget(server, perServer: 1000),
        throwsA(isA<McpBudgetExceeded>()),
      );
    });

    test('the instructions say when to call and how to cite, and no more', () {
      expect(kLintcruxMcpInstructions.length, lessThanOrEqualTo(600));
      expect(kLintcruxMcpInstructions, contains('file:line'));
      expect(kLintcruxMcpInstructions, contains('engine_error'));
      for (final banned in <String>['\u2014', 'better', 'faster', 'honest']) {
        expect(kLintcruxMcpInstructions, isNot(contains(banned)));
      }
    });

    test('nothing that writes or weakens the gate is offered', () {
      final names = <String>{
        for (final t in kLintcruxMcpTools)
          for (final f in t.fields) f.name,
      };
      final flags = <String>{
        for (final t in kLintcruxMcpTools)
          for (final f in t.fields) f.flag,
      };
      for (final flag in flags) {
        expect(flag, isNot(endsWith('-path')));
        expect(
          const <String>{
            '--export',
            '--out',
            '--sarif',
            '--baseline',
            '--allow-missing-engines',
            '--config',
            '--import-filelist',
            '--import-edam',
          },
          isNot(contains(flag)),
        );
      }
      expect(names, isNot(contains('baseline')));
    });
  });

  group('protocol', () {
    test(
      'initialize, tools/list and a call through a scripted client',
      () async {
        final client = McpScriptedClient.inProcess(cli.server(root: root))
          ..send(
            '{"jsonrpc":"2.0","id":1,"method":"initialize","params":'
            '{"protocolVersion":"2025-06-18"}}',
          );
        final init = jsonDecode((await client.next())!) as Map<String, Object?>;
        final result = init['result']! as Map<String, Object?>;
        expect(result['protocolVersion'], '2025-06-18');
        expect(result['instructions'], kLintcruxMcpInstructions);
        expect(
          (result['serverInfo']! as Map<String, Object?>)['name'],
          'lintcrux',
        );
        client.send('{"jsonrpc":"2.0","id":2,"method":"tools/list"}');
        final list = jsonDecode((await client.next())!) as Map<String, Object?>;
        final tools =
            (list['result']! as Map<String, Object?>)['tools']!
                as List<Object?>;
        expect(
          tools.map((t) => (t! as Map<String, Object?>)['name']),
          <String>['lint', 'rule', 'waivers'],
        );
        client.send(
          '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":'
          '"rule","arguments":{"id":"verilator/WIDTH"}}}',
        );
        final answer =
            jsonDecode((await client.next())!) as Map<String, Object?>;
        expect(
          (answer['result']! as Map<String, Object?>)['isError'],
          isFalse,
        );
        await client.close();
      },
    );

    test('lintcrux mcp refuses a root that is not a directory', () async {
      final err = <String>[];
      final code = await cli.run(
        <String>['mcp', '--root', p.join(tmp.path, 'missing')],
        stdoutSink: (_) {},
        stderrSink: err.add,
      );
      expect(code, 64);
      expect(err.join('\n'), contains('is not a directory'));
    });

    test('lintcrux mcp --help answers without serving', () async {
      final out = <String>[];
      final code = await cli.run(
        <String>['mcp', '--help'],
        stdoutSink: out.add,
        stderrSink: (_) {},
      );
      expect(code, 0);
      expect(out.join('\n'), contains('lintcrux mcp [--root <dir>]'));
      expect(LintcruxCli.isHelpOrVersion(<String>['mcp', '--help']), isTrue);
      expect(LintcruxCli.isHelpOrVersion(<String>['mcp']), isFalse);
    });
  });

  group('confinement: a refused path is never run or read', () {
    late String outside;

    setUp(() {
      outside = p.join(tmp.path, 'outside');
      Directory(outside).createSync();
      File(
        p.join(outside, 'top.sv'),
      ).writeAsStringSync('module top; endmodule\n');
      File(p.join(outside, 'p.lintcrux')).writeAsStringSync(
        jsonEncode(<String, Object?>{
          'version': 1,
          'name': 'p',
          'rootPath': '.',
          'sourceFiles': <String>['top.sv'],
          'language': 'systemverilog',
        }),
      );
    });

    Future<void> expectRefused(
      String tool,
      Map<String, Object?> arguments,
    ) async {
      final doc = await call(tool, arguments);
      expect(doc['outcome'], 'usage_error', reason: '$arguments');
      expect(engine('verilator').requests, isEmpty, reason: 'an engine ran');
      expect(engine('verible').requests, isEmpty, reason: 'an engine ran');
    }

    test('the check would see a run: a project inside is linted', () async {
      final doc = await call('lint', <String, Object?>{
        'project': 'design/design.lintcrux',
      });
      expect(doc['outcome'], 'completed');
      expect(engine('verilator').requests, hasLength(1));
    });

    test('a project outside the root', () async {
      await expectRefused('lint', <String, Object?>{
        'project': p.join(outside, 'p.lintcrux'),
      });
      await expectRefused('lint', <String, Object?>{
        'project': '../outside/p.lintcrux',
      });
      await expectRefused('waivers', <String, Object?>{
        'project': p.join(outside, 'p.lintcrux'),
      });
    });

    test('a source file outside the root', () async {
      await expectRefused('lint', <String, Object?>{
        'files': <String>['design/rtl/top.sv', p.join(outside, 'top.sv')],
      });
    });

    test('a symbolic link out of the root', () async {
      Link(p.join(root, 'link.lintcrux')).createSync(
        p.join(outside, 'p.lintcrux'),
      );
      Link(p.join(root, 'linked')).createSync(outside);
      await expectRefused('lint', <String, Object?>{
        'project': 'link.lintcrux',
      });
      await expectRefused('lint', <String, Object?>{
        'files': <String>['linked/top.sv'],
      });
    }, testOn: '!windows');

    test('a project inside that names a file outside', () async {
      for (final (key, value) in <(String, Object?)>[
        ('sourceFiles', <String>[p.join(outside, 'top.sv')]),
        ('includePaths', <String>[outside]),
        ('rootPath', outside),
        (
          'perEngineOptions',
          <String, Object?>{
            'verilator': <String, Object?>{
              'waiverFiles': <String>[p.join(outside, 'w.vlt')],
            },
          },
        ),
        (
          'perEngineOptions',
          <String, Object?>{
            'svlint': <String, Object?>{
              'configPath': p.join(outside, '.svlint.toml'),
            },
          },
        ),
        (
          'perEngineOptions',
          <String, Object?>{
            'yosys': <String, Object?>{'workingDirectory': outside},
          },
        ),
        (
          'perEngineOptions',
          <String, Object?>{
            'rohd': <String, Object?>{'sidecar': outside},
          },
        ),
      ]) {
        File(p.join(root, 'named.lintcrux')).writeAsStringSync(
          jsonEncode(<String, Object?>{
            'version': 1,
            'name': 'named',
            'rootPath': '.',
            'sourceFiles': <String>['design/rtl/top.sv'],
            'language': 'systemverilog',
            key: value,
          }),
        );
        await expectRefused('lint', <String, Object?>{
          'project': 'named.lintcrux',
        });
      }
    });

    test('a network or device path', () async {
      for (final path in <String>[
        r'\\server\share\p.lintcrux',
        '//server/share/p.lintcrux',
        r'\\?\C:\p.lintcrux',
      ]) {
        await expectRefused('lint', <String, Object?>{'project': path});
      }
    });

    test('raw engine flags in a project are not run', () async {
      File(p.join(root, 'flags.lintcrux')).writeAsStringSync(
        jsonEncode(<String, Object?>{
          'version': 1,
          'name': 'flags',
          'rootPath': '.',
          'sourceFiles': <String>['design/rtl/top.sv'],
          'language': 'systemverilog',
          'perEngineOptions': <String, Object?>{
            'verible': <String, Object?>{
              'extraOptions': <String>['--rules_config=/etc/x'],
            },
          },
        }),
      );
      await expectRefused('lint', <String, Object?>{
        'project': 'flags.lintcrux',
      });
    });
  });

  group('paging reuses the run', () {
    test('a later page of the same call runs no engine', () async {
      final server = cli.server(root: root);
      final first = await call('lint', <String, Object?>{
        'project': 'design/design.lintcrux',
        'limit': 2,
      }, server: server);
      final second = await call('lint', <String, Object?>{
        'project': 'design/design.lintcrux',
        'limit': 2,
        'offset': 2,
      }, server: server);
      expect(engine('verilator').requests, hasLength(1));
      final a = first['body']! as Map<String, Object?>;
      final b = second['body']! as Map<String, Object?>;
      expect(a['total'], 5);
      expect(b['offset'], 2);
      expect(b['returned'], 2);
      // The page is the one a fresh run would give.
      final fresh =
          await LintcruxCli(
            registry: specRegistry(SpecScenario.ok),
            installSignalReaper: false,
            withheld: openCoreWithheld,
            mcpTelemetry: () => null,
          ).lintToolDocument(<String>[
            '--limit',
            '2',
            '--offset',
            '2',
            p.join(root, 'design', 'design.lintcrux'),
          ]);
      expect(jsonEncode(second), jsonEncode(fresh.toJson()));
    });

    test('a source that changed runs the engines again', () async {
      final server = cli.server(root: root);
      await call('lint', <String, Object?>{
        'project': 'design/design.lintcrux',
      }, server: server);
      final source = File(p.join(root, 'design', 'rtl', 'fifo.sv'));
      source.writeAsStringSync('${source.readAsStringSync()}// edited\n');
      await call('lint', <String, Object?>{
        'project': 'design/design.lintcrux',
        'offset': 1,
      }, server: server);
      expect(engine('verilator').requests, hasLength(2));
    });

    test('a first page, or other arguments, runs the engines again', () async {
      final server = cli.server(root: root);
      for (final arguments in <Map<String, Object?>>[
        <String, Object?>{'project': 'design/design.lintcrux'},
        <String, Object?>{'project': 'design/design.lintcrux'},
        <String, Object?>{
          'project': 'design/design.lintcrux',
          'top': 'fifo',
          'offset': 1,
        },
      ]) {
        await call('lint', arguments, server: server);
      }
      expect(engine('verilator').requests, hasLength(3));
    });
  });

  group('telemetry', () {
    test(
      'one mcp.tool_call per call: tool, outcome, duration and no more',
      () async {
        final events = <(String, Map<String, Object?>)>[];
        final server = cli.server(
          root: root,
          telemetry: McpTelemetry(
            consented: () => true,
            sink: (name, properties) => events.add((name, properties)),
            environment: const <String, String>{},
          ),
        );
        await call('rule', <String, Object?>{
          'id': 'verilator/WIDTH',
        }, server: server);
        await call('waivers', <String, Object?>{
          'project': '../nowhere.lintcrux',
        }, server: server);
        expect(events, hasLength(2));
        expect(events.first.$1, 'mcp.tool_call');
        expect(events.first.$2, <String, Object?>{
          'tool': 'rule',
          'outcome': 'completed',
          'duration': 'lt_1s',
        });
        expect(events.last.$2['outcome'], 'usage_error');
      },
    );

    test('nothing is counted under CI', () async {
      final events = <String>[];
      final server = cli.server(
        root: root,
        telemetry: McpTelemetry(
          consented: () => true,
          sink: (name, _) => events.add(name),
          environment: const <String, String>{'CI': 'true'},
        ),
      );
      await call('rule', <String, Object?>{
        'id': 'verilator/WIDTH',
      }, server: server);
      expect(events, isEmpty);
    });
  });
}
