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

  group('output GHDL gives that is not a finding', () {
    test('a located finding whose path is refused fails the run', () async {
      final fake = FakeProcessRunner()
        ..exitCode = 1
        ..stderrLines = <String>[
          '../elsewhere/x.vhd:2:10:error: unit "float_pkg" not found',
          'ghdl:error: compilation error',
        ];
      final run = GhdlEngine(runner: fake).run(request()).toList();
      await expectLater(run, throwsA(isA<EngineRunFailedException>()));
    });

    test('the compilation-error trailer after parsed findings is not a '
        'failure', () async {
      final fake = FakeProcessRunner()
        ..exitCode = 1
        ..stderrLines = <String>[
          'a.vhd:2:10:error: unit "float_pkg" not found in library "ieee"',
          'use ieee.float_pkg.all;',
          '         ^',
          'ghdl:error: compilation error',
        ];
      final violations = await GhdlEngine(runner: fake).run(request()).toList();
      expect(violations, hasLength(1));
    });
  });
}
