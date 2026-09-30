// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/services/engines/slang/slang_engine.dart';

import '../fake_process_runner.dart';

const _jsonLine =
    '{"severity":"warning","code":"slang::diag::ImplicitConvert","message":"Implicit conversion","location":{"file":"top.sv","line":42,"column":13}}';

void main() {
  group('SlangEngine', () {
    test('identifies itself with engine id and display name', () {
      final engine = SlangEngine();
      expect(engine.id, 'slang');
      expect(engine.displayName, 'Slang');
    });

    test('capabilities advertise structured output', () {
      final engine = SlangEngine();
      expect(engine.capabilities.emitsStructuredOutput, isTrue);
      expect(engine.capabilities.supportedLanguages, {
        HdlLanguage.systemVerilog,
        HdlLanguage.verilog,
      });
    });

    test('run streams parsed JSON diagnostics from stderr', () async {
      final fake = FakeProcessRunner()..stderrLines = <String>[_jsonLine];
      final engine = SlangEngine(runner: fake, projectRoot: '/work/soc');
      final violations = await engine
          .run(
            const LintRunRequest(
              sourceFiles: ['/work/soc/top.sv'],
              binary: EngineBinaryConfig.system(),
              language: HdlLanguage.systemVerilog,
            ),
          )
          .toList();
      expect(violations, hasLength(1));
      expect(violations.single.engineId, 'slang');
      expect(violations.single.ruleId, 'slang/ImplicitConvert');
      expect(violations.single.severity, Severity.warning);
    });

    test('run also accepts JSON on stdout (some builds)', () async {
      final fake = FakeProcessRunner()..stdoutLines = <String>[_jsonLine];
      final engine = SlangEngine(runner: fake);
      final violations = await engine
          .run(
            const LintRunRequest(
              sourceFiles: ['/x/a.sv'],
              binary: EngineBinaryConfig.system(),
              language: HdlLanguage.systemVerilog,
            ),
          )
          .toList();
      expect(violations, hasLength(1));
    });

    test('run invokes slang with -q --diag-json - by default', () async {
      final fake = FakeProcessRunner();
      final engine = SlangEngine(runner: fake);
      await engine
          .run(
            const LintRunRequest(
              sourceFiles: ['/x/a.sv'],
              binary: EngineBinaryConfig.system(),
              language: HdlLanguage.systemVerilog,
            ),
          )
          .toList();
      final inv = fake.invocations.single;
      expect(inv.executable, 'slang');
      // The JSON mode flag is `--diag-json <file|->` (slang 8.0+), NOT
      // `--json-diagnostics` — that spelling has never existed in slang
      // and makes the process exit with "unknown command line argument",
      // yielding a silent zero-violation run.
      expect(inv.arguments, containsAllInOrder(['--diag-json', '-']));
      expect(inv.arguments, contains('-q'));
      expect(inv.arguments, isNot(contains('--json-diagnostics')));
      expect(inv.arguments, contains('/x/a.sv'));
    });

    test('textModeFallback omits --diag-json and parses text', () async {
      final fake = FakeProcessRunner()
        ..stderrLines = <String>['top.sv:1:1: warning: msg [no-tabs]'];
      final engine = SlangEngine(runner: fake);
      final violations = await engine
          .run(
            const LintRunRequest(
              sourceFiles: ['/x/top.sv'],
              binary: EngineBinaryConfig.system(),
              language: HdlLanguage.systemVerilog,
              options: {'textModeFallback': true},
            ),
          )
          .toList();
      expect(violations, hasLength(1));
      expect(violations.single.ruleId, 'slang/no-tabs');
      expect(
        fake.invocations.single.arguments,
        isNot(contains('--diag-json')),
      );
    });

    test('include paths use -I and defines use -D', () async {
      final fake = FakeProcessRunner();
      final engine = SlangEngine(runner: fake);
      await engine
          .run(
            const LintRunRequest(
              sourceFiles: ['/x/a.sv'],
              binary: EngineBinaryConfig.system(),
              language: HdlLanguage.systemVerilog,
              includePaths: ['/x/include'],
              defines: {'FOO': '1', 'BAR': ''},
            ),
          )
          .toList();
      final args = fake.invocations.single.arguments;
      expect(args, containsAllInOrder(['-I', '/x/include']));
      expect(args, contains('-DFOO=1'));
      expect(args, contains('-DBAR'));
    });

    test('top module is forwarded via --top', () async {
      final fake = FakeProcessRunner();
      final engine = SlangEngine(runner: fake);
      await engine
          .run(
            const LintRunRequest(
              sourceFiles: ['/x/a.sv'],
              binary: EngineBinaryConfig.system(),
              language: HdlLanguage.systemVerilog,
              topModule: 'top',
            ),
          )
          .toList();
      expect(
        fake.invocations.single.arguments,
        containsAllInOrder(['--top', 'top']),
      );
    });

    test('custom binary path is honored', () async {
      final fake = FakeProcessRunner();
      final engine = SlangEngine(runner: fake);
      await engine
          .run(
            const LintRunRequest(
              sourceFiles: ['/x/a.sv'],
              binary: EngineBinaryConfig(
                source: EngineBinarySource.custom,
                path: '/opt/slang/bin/slang',
              ),
              language: HdlLanguage.systemVerilog,
            ),
          )
          .toList();
      expect(fake.invocations.single.executable, '/opt/slang/bin/slang');
    });

    test('run throws EngineNotAvailableException when binary cannot be '
        'launched', () async {
      final fake = FakeProcessRunner()
        ..onStartThrows = const ProcessException(
          'slang',
          [],
          'No such file or directory',
        );
      final engine = SlangEngine(runner: fake);
      await expectLater(
        engine
            .run(
              const LintRunRequest(
                sourceFiles: ['/x/a.sv'],
                binary: EngineBinaryConfig.system(),
                language: HdlLanguage.systemVerilog,
              ),
            )
            .toList(),
        throwsA(
          isA<EngineNotAvailableException>().having(
            (e) => e.engineId,
            'engineId',
            'slang',
          ),
        ),
      );
    });

    test('cancel kills an in-progress subprocess', () async {
      final fake = FakeProcessRunner()
        ..holdOpen = true
        ..stderrLines = <String>[_jsonLine];
      final engine = SlangEngine(runner: fake);
      final future = engine
          .run(
            const LintRunRequest(
              sourceFiles: ['/x/a.sv'],
              binary: EngineBinaryConfig.system(),
              language: HdlLanguage.systemVerilog,
            ),
          )
          .toList();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      engine.cancel();
      await future;
      expect(fake.lastProcess!.killed, isTrue);
    });

    test('cancel before run is a no-op', () {
      SlangEngine(runner: FakeProcessRunner()).cancel();
    });

    test('detectVersion returns the trimmed first non-empty line', () async {
      final fake = FakeProcessRunner()
        ..stdoutLines = const <String>['slang version 5.0'];
      final engine = SlangEngine(runner: fake);
      final version = await engine.detectVersion(
        const EngineBinaryConfig.system(),
      );
      expect(version, 'slang version 5.0');
    });

    test(
      'detectVersion returns null when the subprocess exits non-zero',
      () async {
        final fake = FakeProcessRunner()..exitCode = 1;
        final engine = SlangEngine(runner: fake);
        final version = await engine.detectVersion(
          const EngineBinaryConfig.system(),
        );
        expect(version, isNull);
      },
    );

    test(
      'detectVersion returns null when the binary cannot be launched',
      () async {
        final fake = FakeProcessRunner()
          ..onStartThrows = const ProcessException('slang', []);
        final engine = SlangEngine(runner: fake);
        final version = await engine.detectVersion(
          const EngineBinaryConfig.system(),
        );
        expect(version, isNull);
      },
    );
  });

  group('SlangEngine integration with real binary', () {
    test(
      'detectVersion against system slang',
      () async {
        final engine = SlangEngine();
        final version = await engine.detectVersion(
          const EngineBinaryConfig.system(),
        );
        expect(version, isNotNull);
        expect(version!.trim(), isNotEmpty);
      },
      skip: _slangOnPath() ? false : 'slang not on PATH',
    );
  });
}

bool _slangOnPath() {
  final pathVar = Platform.environment['PATH'] ?? '';
  final exe = Platform.isWindows ? 'slang.exe' : 'slang';
  for (final dir in pathVar.split(Platform.isWindows ? ';' : ':')) {
    if (dir.isEmpty) continue;
    if (File('$dir${Platform.pathSeparator}$exe').existsSync()) return true;
  }
  return false;
}
