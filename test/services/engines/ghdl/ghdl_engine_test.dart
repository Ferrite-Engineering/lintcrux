// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/services/engines/ghdl/ghdl_engine.dart';

import '../fake_process_runner.dart';

void main() {
  group('GhdlEngine', () {
    test('identifies itself with the engine id and display name', () {
      final engine = GhdlEngine();
      expect(engine.id, 'ghdl');
      expect(engine.displayName, 'GHDL');
    });

    test('declares VHDL-only support', () {
      final engine = GhdlEngine();
      expect(
        engine.capabilities.supportedLanguages,
        {HdlLanguage.vhdl},
      );
    });

    test('run streams parsed violations from stderr', () async {
      final fake = FakeProcessRunner()
        ..stderrLines = const <String>[
          'design.vhd:42:13: warning: unused variable "x" [-Wunused]',
        ];
      final engine = GhdlEngine(
        runner: fake,
        projectRoot: '/work/vhdl',
      );
      final violations = await engine
          .run(
            const LintRunRequest(
              sourceFiles: ['/work/vhdl/design.vhd'],
              binary: EngineBinaryConfig.system(),
              language: HdlLanguage.vhdl,
            ),
          )
          .toList();
      expect(violations, hasLength(1));
      expect(violations.single.engineId, 'ghdl');
      expect(violations.single.ruleId, 'ghdl/unused');
      expect(violations.single.severity, Severity.warning);
      expect(violations.single.location.file, '/work/vhdl/design.vhd');
    });

    test(
      'run invokes ghdl with -a + default --warn-* flags + sources',
      () async {
        final fake = FakeProcessRunner();
        final engine = GhdlEngine(runner: fake);
        await engine
            .run(
              const LintRunRequest(
                sourceFiles: ['/x/a.vhd', '/x/b.vhd'],
                binary: EngineBinaryConfig.system(),
                language: HdlLanguage.vhdl,
              ),
            )
            .toList();
        final inv = fake.invocations.single;
        expect(inv.executable, 'ghdl');
        expect(inv.arguments.first, '-a');
        // Default flag set is present.
        for (final flag in GhdlEngine.defaultWarnFlags) {
          expect(inv.arguments, contains('--warn-$flag'));
        }
        expect(inv.arguments, containsAllInOrder(['/x/a.vhd', '/x/b.vhd']));
      },
    );

    test('warnFlags option overrides the default flag set', () async {
      final fake = FakeProcessRunner();
      final engine = GhdlEngine(runner: fake);
      await engine
          .run(
            const LintRunRequest(
              sourceFiles: ['/x/a.vhd'],
              binary: EngineBinaryConfig.system(),
              language: HdlLanguage.vhdl,
              options: {
                'warnFlags': ['binding', 'reserved'],
              },
            ),
          )
          .toList();
      final args = fake.invocations.single.arguments;
      expect(args, contains('--warn-binding'));
      expect(args, contains('--warn-reserved'));
      expect(args, isNot(contains('--warn-unused')));
    });

    test('explicit empty warnFlags list disables all warnings', () async {
      final fake = FakeProcessRunner();
      final engine = GhdlEngine(runner: fake);
      await engine
          .run(
            const LintRunRequest(
              sourceFiles: ['/x/a.vhd'],
              binary: EngineBinaryConfig.system(),
              language: HdlLanguage.vhdl,
              options: {
                'warnFlags': <String>[],
              },
            ),
          )
          .toList();
      final args = fake.invocations.single.arguments;
      expect(args.where((a) => a.startsWith('--warn-')), isEmpty);
    });

    test('custom binary path is honored', () async {
      final fake = FakeProcessRunner();
      final engine = GhdlEngine(runner: fake);
      await engine
          .run(
            const LintRunRequest(
              sourceFiles: ['/x/a.vhd'],
              binary: EngineBinaryConfig(
                source: EngineBinarySource.custom,
                path: '/opt/ghdl-4.1.0/bin/ghdl',
              ),
              language: HdlLanguage.vhdl,
            ),
          )
          .toList();
      expect(
        fake.invocations.single.executable,
        '/opt/ghdl-4.1.0/bin/ghdl',
      );
    });

    test(
      'throws EngineNotAvailableException when binary cannot be launched',
      () async {
        final fake = FakeProcessRunner()
          ..onStartThrows = const ProcessException(
            'ghdl',
            ['-a'],
            'No such file or directory',
          );
        final engine = GhdlEngine(runner: fake);
        await expectLater(
          engine
              .run(
                const LintRunRequest(
                  sourceFiles: ['/x/a.vhd'],
                  binary: EngineBinaryConfig.system(),
                  language: HdlLanguage.vhdl,
                ),
              )
              .toList(),
          throwsA(
            isA<EngineNotAvailableException>().having(
              (e) => e.engineId,
              'engineId',
              'ghdl',
            ),
          ),
        );
      },
    );

    test('cancel kills an in-progress subprocess', () async {
      final fake = FakeProcessRunner()
        ..holdOpen = true
        ..stderrLines = const <String>[
          'design.vhd:1:1: warning: msg',
        ];
      final engine = GhdlEngine(runner: fake);
      final future = engine
          .run(
            const LintRunRequest(
              sourceFiles: ['/x/a.vhd'],
              binary: EngineBinaryConfig.system(),
              language: HdlLanguage.vhdl,
            ),
          )
          .toList();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      engine.cancel();
      await future;
      expect(fake.lastProcess!.killed, isTrue);
    });

    test('cancel before run is a no-op (does not crash)', () {
      GhdlEngine(runner: FakeProcessRunner()).cancel();
    });

    test('detectVersion returns the trimmed first non-empty line', () async {
      final fake = FakeProcessRunner()
        ..stdoutLines = const <String>['GHDL 4.1.0 (Ubuntu)'];
      final engine = GhdlEngine(runner: fake);
      final version = await engine.detectVersion(
        const EngineBinaryConfig.system(),
      );
      expect(version, 'GHDL 4.1.0 (Ubuntu)');
    });

    test(
      'detectVersion returns null when the subprocess exits non-zero',
      () async {
        final fake = FakeProcessRunner()..exitCode = 1;
        final engine = GhdlEngine(runner: fake);
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
          ..onStartThrows = const ProcessException('ghdl', []);
        final engine = GhdlEngine(runner: fake);
        final version = await engine.detectVersion(
          const EngineBinaryConfig.system(),
        );
        expect(version, isNull);
      },
    );
  });

  group('GhdlEngine integration with real binary', () {
    test(
      'detectVersion against system ghdl',
      () async {
        final engine = GhdlEngine();
        final version = await engine.detectVersion(
          const EngineBinaryConfig.system(),
        );
        expect(version, isNotNull);
        expect(version!.trim(), isNotEmpty);
      },
      skip: _ghdlOnPath() ? false : 'ghdl not on PATH',
    );
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
