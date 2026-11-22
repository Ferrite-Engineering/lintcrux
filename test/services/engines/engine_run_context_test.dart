// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/services/engines/engine_run_context.dart';
import 'package:lintcrux/services/engines/ghdl/ghdl_engine.dart';
import 'package:lintcrux/services/engines/slang/slang_engine.dart';
import 'package:lintcrux/services/engines/svlint/svlint_engine.dart';
import 'package:lintcrux/services/engines/verible/verible_engine.dart';
import 'package:lintcrux/services/engines/verilator/verilator_engine.dart';
import 'package:path/path.dart' as p;

import 'fake_process_runner.dart';

LintRunRequest _request({
  required List<String> sources,
  String projectRoot = '',
  Map<String, Object?> options = const <String, Object?>{},
  HdlLanguage language = HdlLanguage.systemVerilog,
}) => LintRunRequest(
  sourceFiles: sources,
  binary: const EngineBinaryConfig.system(),
  language: language,
  projectRoot: projectRoot,
  options: options,
);

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lintcrux_run_context_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('engineRootPath', () {
    test('is the project root when the request carries one', () {
      final root = tmp.path;
      expect(
        engineRootPath(
          _request(
            sources: <String>[
              p.join(root, 'a', 'x.sv'),
              p.join(root, 'b', 't.sv'),
            ],
            projectRoot: root,
          ),
        ),
        root,
      );
    });

    test('is the first source file folder for a request with no project', () {
      expect(
        engineRootPath(_request(sources: <String>['/work/a/x.sv'])),
        '/work/a',
      );
    });

    test('is the configured root when the request has no usable root', () {
      expect(
        engineRootPath(
          _request(sources: <String>['/work/a/x.sv']),
          configuredRoot: '/work',
        ),
        '/work',
      );
    });

    test('skips a project root that is not a directory on this machine', () {
      // A `.lintcrux` carrying an absolute `rootPath` written elsewhere must
      // not turn into an engine that cannot start.
      expect(
        engineRootPath(
          _request(
            sources: <String>['/work/a/x.sv'],
            projectRoot: p.join(tmp.path, 'gone'),
          ),
        ),
        '/work/a',
      );
    });

    test('is empty when there is nothing to go on', () {
      expect(engineRootPath(_request(sources: const <String>[])), '');
    });
  });

  group('engineStringListOption', () {
    test('reads a list of strings and skips empty and non-string entries', () {
      final request = _request(
        sources: const <String>[],
        options: const <String, Object?>{
          'extraOptions': <Object?>['--a', '', 3, '--b'],
        },
      );
      expect(engineStringListOption(request, 'extraOptions'), <String>[
        '--a',
        '--b',
      ]);
    });

    test('is empty when the key is absent or not a list', () {
      expect(
        engineStringListOption(_request(sources: const <String>[]), 'x'),
        isEmpty,
      );
      expect(
        engineStringListOption(
          _request(
            sources: const <String>[],
            options: const <String, Object?>{'x': '--a'},
          ),
          'x',
        ),
        isEmpty,
      );
    });
  });

  // Every engine runs where the project says, not wherever the first source
  // file happens to be, and every engine takes `extraOptions` the same way.
  group('every engine', () {
    final engines = <String, LintEngine Function(FakeProcessRunner)>{
      'slang': (r) => SlangEngine(runner: r),
      'verilator': (r) => VerilatorEngine(runner: r),
      'verible': (r) => VeribleEngine(runner: r),
      'svlint': (r) => SvlintEngine(runner: r),
      'ghdl': (r) => GhdlEngine(runner: r),
    };

    for (final entry in engines.entries) {
      final language = entry.key == 'ghdl'
          ? HdlLanguage.vhdl
          : HdlLanguage.systemVerilog;
      final ext = entry.key == 'ghdl' ? 'vhd' : 'sv';

      test('${entry.key} runs in the project root, not the first source '
          'folder', () async {
        final fake = FakeProcessRunner();
        await entry
            .value(fake)
            .run(
              _request(
                sources: <String>[
                  p.join(tmp.path, '3.build', 'gen', 'first.$ext'),
                  p.join(tmp.path, '1.hw', 'second.$ext'),
                ],
                projectRoot: tmp.path,
                language: language,
              ),
            )
            .toList();
        expect(fake.invocations.first.workingDirectory, tmp.path);
      });

      test('${entry.key} appends extraOptions before the sources', () async {
        final fake = FakeProcessRunner();
        final source = p.join(tmp.path, 'a.$ext');
        await entry
            .value(fake)
            .run(
              _request(
                sources: <String>[source],
                projectRoot: tmp.path,
                language: language,
                options: const <String, Object?>{
                  'extraOptions': <String>['--flag-one', '--flag-two=2'],
                },
              ),
            )
            .toList();
        final args = fake.invocations.first.arguments;
        expect(
          args,
          containsAllInOrder(<String>['--flag-one', '--flag-two=2']),
        );
        expect(args.indexOf('--flag-two=2'), lessThan(args.indexOf(source)));
      });
    }
  });

  test('a relative Verilator waiver file is looked up from the project root, '
      'whatever folder the first source is in', () async {
    final fake = FakeProcessRunner();
    await VerilatorEngine(runner: fake)
        .run(
          _request(
            sources: <String>[p.join(tmp.path, 'deep', 'er', 'first.sv')],
            projectRoot: tmp.path,
            options: const <String, Object?>{
              'waiverFiles': <String>['waivers/lint.vlt'],
            },
          ),
        )
        .toList();
    final inv = fake.invocations.first;
    expect(inv.arguments, contains('waivers/lint.vlt'));
    expect(inv.workingDirectory, tmp.path);
  });
}
