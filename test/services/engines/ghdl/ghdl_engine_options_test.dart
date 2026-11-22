// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/services/engines/ghdl/ghdl_engine.dart';
import 'package:path/path.dart' as p;

import '../fake_process_runner.dart';

void main() {
  late Directory tmp;

  LintRunRequest request({
    List<String>? sources,
    Map<String, Object?> options = const <String, Object?>{},
  }) => LintRunRequest(
    sourceFiles: sources ?? <String>[p.join(tmp.path, 'a.vhd')],
    binary: const EngineBinaryConfig.system(),
    language: HdlLanguage.vhdl,
    projectRoot: tmp.path,
    options: options,
  );

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lintcrux_ghdl_options_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('invocation', () {
    test('analyses with -a and no --std by default', () async {
      final fake = FakeProcessRunner();
      await GhdlEngine(runner: fake).run(request()).toList();
      final args = fake.invocations.single.arguments;
      expect(args.first, '-a');
      expect(args.where((a) => a.startsWith('--std')), isEmpty);
    });

    test('std is passed as --std=<value>, ahead of the sources', () async {
      final fake = FakeProcessRunner();
      await GhdlEngine(
        runner: fake,
      ).run(request(options: const <String, Object?>{'std': '08'})).toList();
      final args = fake.invocations.single.arguments;
      expect(args, contains('--std=08'));
      expect(
        args.indexOf('--std=08'),
        lessThan(args.indexOf(p.join(tmp.path, 'a.vhd'))),
      );
    });

    test('syntaxOnly runs ghdl -s in place of ghdl -a', () async {
      final fake = FakeProcessRunner();
      await GhdlEngine(runner: fake)
          .run(request(options: const <String, Object?>{'syntaxOnly': true}))
          .toList();
      final args = fake.invocations.single.arguments;
      expect(args.first, '-s');
      expect(args, isNot(contains('-a')));
    });

    test('the sources keep the project order', () async {
      final sources = <String>[
        p.join(tmp.path, 'pkg.vhd'),
        p.join(tmp.path, 'a', 'use.vhd'),
        p.join(tmp.path, 'b', 'top.vhd'),
      ];
      final fake = FakeProcessRunner();
      await GhdlEngine(runner: fake).run(request(sources: sources)).toList();
      final args = fake.invocations.single.arguments;
      expect(args.sublist(args.length - 3), sources);
    });

    test(
      'a std that is not a string fails the engine before GHDL runs',
      () async {
        final fake = FakeProcessRunner();
        final run = GhdlEngine(
          runner: fake,
        ).run(request(options: const <String, Object?>{'std': 8})).toList();
        await expectLater(run, throwsA(isA<EngineRunFailedException>()));
        expect(fake.invocations, isEmpty);
      },
    );
  });

  group('a standard GHDL rejects', () {
    test(
      'an unknown --std fails the run instead of reading as clean',
      () async {
        final fake = FakeProcessRunner()
          ..exitCode = 1
          ..stderrLines = <String>[
            'ghdl:error: unknown language standard: 99. Should be one of: 87',
          ];
        final run = GhdlEngine(
          runner: fake,
        ).run(request(options: const <String, Object?>{'std': '99'})).toList();
        await expectLater(
          run,
          throwsA(
            isA<EngineRunFailedException>().having(
              (e) => e.outputExcerpt.single,
              'excerpt',
              contains('unknown language standard'),
            ),
          ),
        );
      },
    );
  });

  group('with a real GHDL', () {
    // A VHDL-2008 design: `ieee.float_pkg` exists only under --std=08.
    const source = '''
library ieee;
use ieee.float_pkg.all;
entity e is end;
architecture a of e is
  signal unused : float32;
begin
end;
''';

    Future<List<String>> ruleIds(Map<String, Object?> options) async {
      final file = File(p.join(tmp.path, 'a.vhd'))..writeAsStringSync(source);
      final violations = await GhdlEngine()
          .run(request(sources: <String>[file.path], options: options))
          .toList();
      return <String>[for (final v in violations) v.ruleId];
    }

    test('the default standard cannot read a VHDL-2008 design', () async {
      expect(
        await ruleIds(const <String, Object?>{}),
        contains('ghdl/UNCLASSIFIED'),
      );
    }, skip: _ghdlOnPath() ? false : 'ghdl not on PATH');

    test('std 08 reads it, with and without syntaxOnly', () async {
      for (final syntaxOnly in <bool>[false, true]) {
        final rules = await ruleIds(<String, Object?>{
          'std': '08',
          'syntaxOnly': syntaxOnly,
        });
        expect(
          rules,
          contains('ghdl/unused'),
          reason: 'syntaxOnly=$syntaxOnly',
        );
        expect(rules, isNot(contains('ghdl/UNCLASSIFIED')));
      }
    }, skip: _ghdlOnPath() ? false : 'ghdl not on PATH');

    test('an unknown std fails the run', () async {
      await expectLater(
        ruleIds(const <String, Object?>{'std': '99'}),
        throwsA(isA<EngineRunFailedException>()),
      );
    }, skip: _ghdlOnPath() ? false : 'ghdl not on PATH');
  });
}

bool _ghdlOnPath() {
  final pathVar = Platform.environment['PATH'] ?? '';
  final exe = Platform.isWindows ? 'ghdl.exe' : 'ghdl';
  for (final dir in pathVar.split(Platform.isWindows ? ';' : ':')) {
    if (dir.isEmpty) continue;
    if (File('$dir${Platform.pathSeparator}$exe').existsSync()) return true;
  }
  return false;
}
