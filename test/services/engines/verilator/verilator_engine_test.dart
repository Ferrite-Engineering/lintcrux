// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/services/engines/verilator/verilator_engine.dart';
import 'package:path/path.dart' as p;

import '../fake_process_runner.dart';

void main() {
  group('VerilatorEngine', () {
    test('identifies itself with the engine id and display name', () {
      final engine = VerilatorEngine();
      expect(engine.id, 'verilator');
      expect(engine.displayName, 'Verilator');
    });

    test('declares Verilog and SystemVerilog support', () {
      final engine = VerilatorEngine();
      expect(engine.capabilities.supportedLanguages, {
        HdlLanguage.verilog,
        HdlLanguage.systemVerilog,
      });
    });

    test('run streams parsed violations from stderr', () async {
      final fake = FakeProcessRunner()
        ..stderrLines = <String>[
          '%Warning-UNUSEDSIGNAL: top.sv:42:13: unused',
          '   42 | logic x;',
        ];
      final engine = VerilatorEngine(
        runner: fake,
        projectRoot: '/work/soc',
      );
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
      expect(violations.single.engineId, 'verilator');
      expect(violations.single.ruleId, 'verilator/UNUSEDSIGNAL');
      expect(violations.single.severity, Severity.warning);
      expect(violations.single.location.file, '/work/soc/top.sv');
    });

    test(
      'run invokes verilator with --lint-only + includes + defines',
      () async {
        final fake = FakeProcessRunner();
        final engine = VerilatorEngine(runner: fake);
        await engine
            .run(
              const LintRunRequest(
                sourceFiles: ['/x/a.sv', '/x/b.sv'],
                includePaths: ['/inc/foo', '/inc/bar'],
                defines: {'WIDTH': '8', 'DEBUG': ''},
                topModule: 'top',
                binary: EngineBinaryConfig.system(),
                language: HdlLanguage.systemVerilog,
              ),
            )
            .toList();
        final inv = fake.invocations.single;
        expect(inv.executable, 'verilator');
        expect(inv.arguments, contains('--lint-only'));
        expect(inv.arguments, contains('+incdir+/inc/foo'));
        expect(inv.arguments, contains('+incdir+/inc/bar'));
        expect(inv.arguments, contains('+define+WIDTH=8'));
        expect(inv.arguments, contains('+define+DEBUG'));
        expect(inv.arguments, containsAllInOrder(['--top-module', 'top']));
        expect(inv.arguments, containsAllInOrder(['/x/a.sv', '/x/b.sv']));
      },
    );

    group('warnFlags', () {
      test('defaults to -Wall', () async {
        // Not cosmetic. UNUSEDSIGNAL, UNDRIVEN, DECLFILENAME, PINMISSING,
        // VARHIDDEN, UNUSEDPARAM and the rest of Verilator's opt-in set
        // cannot fire without it. An earlier revision of this engine
        // passed no warning flags at all and a project whose only defects
        // were in that set linted green.
        final fake = FakeProcessRunner();
        final engine = VerilatorEngine(runner: fake);
        await engine
            .run(
              const LintRunRequest(
                sourceFiles: ['/x/a.sv'],
                binary: EngineBinaryConfig.system(),
                language: HdlLanguage.systemVerilog,
              ),
            )
            .toList();
        expect(fake.invocations.single.arguments, contains('-Wall'));
        expect(VerilatorEngine.defaultWarnFlags, <String>['all']);
      });

      test('an explicit list replaces the default, -W prefixed', () async {
        final fake = FakeProcessRunner();
        final engine = VerilatorEngine(runner: fake);
        await engine
            .run(
              const LintRunRequest(
                sourceFiles: ['/x/a.sv'],
                binary: EngineBinaryConfig.system(),
                language: HdlLanguage.systemVerilog,
                options: <String, Object?>{
                  'warnFlags': <String>['all', 'no-DECLFILENAME'],
                },
              ),
            )
            .toList();
        final args = fake.invocations.single.arguments;
        expect(args, containsAllInOrder(['-Wall', '-Wno-DECLFILENAME']));
      });

      test('an explicit empty list means "no opt-in warnings"', () async {
        // Mirrors GhdlEngine: an empty list is a choice, not a request for
        // the defaults.
        final fake = FakeProcessRunner();
        final engine = VerilatorEngine(runner: fake);
        await engine
            .run(
              const LintRunRequest(
                sourceFiles: ['/x/a.sv'],
                binary: EngineBinaryConfig.system(),
                language: HdlLanguage.systemVerilog,
                options: <String, Object?>{'warnFlags': <String>[]},
              ),
            )
            .toList();
        expect(
          fake.invocations.single.arguments.where((a) => a.startsWith('-W')),
          isEmpty,
        );
      });

      test('a non-list value falls back to the default', () async {
        final fake = FakeProcessRunner();
        final engine = VerilatorEngine(runner: fake);
        await engine
            .run(
              const LintRunRequest(
                sourceFiles: ['/x/a.sv'],
                binary: EngineBinaryConfig.system(),
                language: HdlLanguage.systemVerilog,
                options: <String, Object?>{'warnFlags': 'all'},
              ),
            )
            .toList();
        expect(fake.invocations.single.arguments, contains('-Wall'));
      });
    });

    group('extraOptions / waiverFiles', () {
      test('extraOptions are appended verbatim before the sources', () async {
        final fake = FakeProcessRunner();
        final engine = VerilatorEngine(runner: fake);
        await engine
            .run(
              const LintRunRequest(
                sourceFiles: ['/x/a.sv'],
                binary: EngineBinaryConfig.system(),
                language: HdlLanguage.systemVerilog,
                options: <String, Object?>{
                  'extraOptions': <String>['-GW=4', '--timing'],
                },
              ),
            )
            .toList();
        expect(
          fake.invocations.single.arguments,
          containsAllInOrder(['-GW=4', '--timing', '/x/a.sv']),
        );
      });

      test('waiverFiles precede the sources they waive', () async {
        // Verilator applies a `.vlt` config only to files after it on
        // the command line — the ordering is the feature, and it is
        // the ordering Edalize's own Verilator backend uses.
        final fake = FakeProcessRunner();
        final engine = VerilatorEngine(runner: fake);
        await engine
            .run(
              const LintRunRequest(
                sourceFiles: ['/x/a.sv'],
                binary: EngineBinaryConfig.system(),
                language: HdlLanguage.systemVerilog,
                options: <String, Object?>{
                  'waiverFiles': <String>['/x/waivers.vlt'],
                },
              ),
            )
            .toList();
        expect(
          fake.invocations.single.arguments,
          containsAllInOrder(['/x/waivers.vlt', '/x/a.sv']),
        );
      });

      test(
        'mistyped values are ignored rather than crashing the run',
        () async {
          final fake = FakeProcessRunner();
          final engine = VerilatorEngine(runner: fake);
          await engine
              .run(
                const LintRunRequest(
                  sourceFiles: ['/x/a.sv'],
                  binary: EngineBinaryConfig.system(),
                  language: HdlLanguage.systemVerilog,
                  options: <String, Object?>{
                    'extraOptions': 'not-a-list',
                    'waiverFiles': 42,
                  },
                ),
              )
              .toList();
          expect(fake.invocations.single.arguments, contains('/x/a.sv'));
        },
      );
    });

    test('custom binary path is honored', () async {
      final fake = FakeProcessRunner();
      final engine = VerilatorEngine(runner: fake);
      await engine
          .run(
            const LintRunRequest(
              sourceFiles: ['/x/a.sv'],
              binary: EngineBinaryConfig(
                source: EngineBinarySource.custom,
                path: '/opt/verilator-5.022/bin/verilator',
              ),
              language: HdlLanguage.systemVerilog,
            ),
          )
          .toList();
      expect(
        fake.invocations.single.executable,
        '/opt/verilator-5.022/bin/verilator',
      );
    });

    test('run throws EngineNotAvailableException when binary cannot be '
        'launched', () async {
      final fake = FakeProcessRunner()
        ..onStartThrows = const ProcessException(
          'verilator',
          ['--lint-only'],
          'No such file or directory',
        );
      final engine = VerilatorEngine(runner: fake);
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
            'verilator',
          ),
        ),
      );
    });

    test('cancel kills an in-progress subprocess', () async {
      final fake = FakeProcessRunner()
        ..holdOpen = true
        ..stderrLines = <String>[
          '%Warning-X: top.sv:1:1: msg',
        ];
      final engine = VerilatorEngine(runner: fake);
      final future = engine
          .run(
            const LintRunRequest(
              sourceFiles: ['/x/a.sv'],
              binary: EngineBinaryConfig.system(),
              language: HdlLanguage.systemVerilog,
            ),
          )
          .toList();
      // Let the engine start the subprocess and attach listeners.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      engine.cancel();
      await future;
      expect(fake.lastProcess!.killed, isTrue);
    });

    test('cancel before run is a no-op (does not crash)', () {
      // Should not throw.
      VerilatorEngine(runner: FakeProcessRunner()).cancel();
    });

    test('detectVersion returns the trimmed first non-empty line', () async {
      final fake = FakeProcessRunner()
        ..stdoutLines = const <String>['Verilator 5.022 2024-07-01 rev v5.022'];
      final engine = VerilatorEngine(runner: fake);
      final version = await engine.detectVersion(
        const EngineBinaryConfig.system(),
      );
      expect(version, 'Verilator 5.022 2024-07-01 rev v5.022');
    });

    test(
      'detectVersion returns null when the subprocess exits non-zero',
      () async {
        final fake = FakeProcessRunner()..exitCode = 1;
        final engine = VerilatorEngine(runner: fake);
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
          ..onStartThrows = const ProcessException('verilator', []);
        final engine = VerilatorEngine(runner: fake);
        final version = await engine.detectVersion(
          const EngineBinaryConfig.system(),
        );
        expect(version, isNull);
      },
    );

    test(
      'detectVersion reads version from stderr when stdout is empty',
      () async {
        // Some Verilator versions emit `--version` on stderr.
        final fake = FakeProcessRunner()
          ..stderrLines = const <String>['Verilator 4.220 devel'];
        final engine = VerilatorEngine(runner: fake);
        final version = await engine.detectVersion(
          const EngineBinaryConfig.system(),
        );
        expect(version, 'Verilator 4.220 devel');
      },
    );

    test(
      'run spawns verilator with the project root as its working directory',
      () async {
        final fake = FakeProcessRunner();
        final engine = VerilatorEngine(runner: fake, projectRoot: '/work/soc');
        await engine
            .run(
              const LintRunRequest(
                // Relative source path — resolvable only via the working
                // directory, which must be the project root.
                sourceFiles: ['cdc_capture.v'],
                binary: EngineBinaryConfig.system(),
                language: HdlLanguage.verilog,
              ),
            )
            .toList();
        expect(fake.invocations.single.workingDirectory, '/work/soc');
      },
    );

    test(
      'run surfaces a fatal %Error with zero violations as an '
      'EngineRunFailedException (never a silent clean run)',
      () async {
        final fake = FakeProcessRunner()
          ..exitCode = 1
          ..stderrLines = <String>[
            "%Error: Cannot find file containing module: 'cdc_capture.v'",
            '%Error: Exiting due to 1 error(s)',
          ];
        final engine = VerilatorEngine(runner: fake, projectRoot: '/work/soc');
        await expectLater(
          engine
              .run(
                const LintRunRequest(
                  sourceFiles: ['cdc_capture.v'],
                  binary: EngineBinaryConfig.system(),
                  language: HdlLanguage.verilog,
                ),
              )
              .toList(),
          throwsA(
            isA<EngineRunFailedException>()
                .having((e) => e.engineId, 'engineId', 'verilator')
                .having((e) => e.exitCode, 'exitCode', 1)
                .having(
                  (e) => e.reason,
                  'reason',
                  contains('Cannot find file'),
                ),
          ),
        );
      },
    );

    test(
      'run does NOT fail when a non-zero exit still carries parsed '
      'violations (verilator exits non-zero merely on finding lints)',
      () async {
        final fake = FakeProcessRunner()
          ..exitCode = 1
          ..stderrLines = <String>[
            '%Warning-WIDTHTRUNC: cdc_capture.v:34:24: truncates async_in',
            '%Error: Exiting due to 1 warning(s)',
          ];
        final engine = VerilatorEngine(runner: fake, projectRoot: '/work/soc');
        final violations = await engine
            .run(
              const LintRunRequest(
                sourceFiles: ['cdc_capture.v'],
                binary: EngineBinaryConfig.system(),
                language: HdlLanguage.verilog,
              ),
            )
            .toList();
        expect(violations, hasLength(1));
        expect(violations.single.ruleId, 'verilator/WIDTHTRUNC');
      },
    );
  });

  group('VerilatorEngine integration with real binary', () {
    test(
      'detectVersion against system verilator',
      () async {
        final engine = VerilatorEngine();
        final version = await engine.detectVersion(
          const EngineBinaryConfig.system(),
        );
        // We don't assert the exact string — different machines have
        // different versions — but it must be non-null and non-empty.
        expect(version, isNotNull);
        expect(version!.trim(), isNotEmpty);
      },
      skip: _verilatorOnPath() ? false : 'verilator not on PATH',
    );

    test(
      'lints the cdc_capture fixture from a foreign working directory '
      '(relative source + absolute project root => WIDTHTRUNC + '
      'UNUSEDSIGNAL on guard_band)',
      () async {
        final fixtureDir = p.join(
          Directory.current.path,
          'test',
          'fixtures',
          'verilog',
          'relative_path_regression',
        );
        // The project root is the ABSOLUTE fixture directory, but the source
        // path handed to the engine is RELATIVE (as authored in
        // `project.lintcrux`). The process CWD during `flutter test` is the
        // package root, NOT the fixture dir, so `cdc_capture.v` is resolvable
        // ONLY via the engine's working-directory = project root. This is the
        // exact regression: before the fix Verilator was spawned with the
        // relative path and no working directory, answered `%Error: Cannot
        // find file`, and reported a silent "Completed, 0 violations".
        final engine = VerilatorEngine(projectRoot: fixtureDir);
        final violations = await engine
            .run(
              const LintRunRequest(
                sourceFiles: ['cdc_capture.v'],
                // -Wall enables UNUSEDSIGNAL (WIDTHTRUNC is on by default).
                binary: EngineBinaryConfig.system(extraArgs: ['-Wall']),
                language: HdlLanguage.verilog,
              ),
            )
            .toList();

        final rules = violations.map((v) => v.ruleId).toSet();
        expect(
          rules,
          containsAll(<String>[
            'verilator/WIDTHTRUNC',
            'verilator/UNUSEDSIGNAL',
          ]),
          reason:
              'file was found and both lints parsed: '
              '${violations.map((v) => v.message).toList()}',
        );
        // The lints land on guard_band, not on the synchronizer stage.
        expect(
          violations.any((v) => v.message.contains('guard_band')),
          isTrue,
        );
        expect(
          violations.any((v) => v.message.contains('sync_stage')),
          isFalse,
        );
        // Every location resolved to the absolute fixture file path.
        final expectedFile = p.join(fixtureDir, 'cdc_capture.v');
        expect(
          violations.every((v) => v.location.file == expectedFile),
          isTrue,
        );
      },
      skip: _verilatorOnPath() ? false : 'verilator not on PATH',
    );
  });
}

bool _verilatorOnPath() {
  final pathVar = Platform.environment['PATH'] ?? '';
  final exe = Platform.isWindows ? 'verilator.exe' : 'verilator';
  for (final dir in pathVar.split(Platform.isWindows ? ';' : ':')) {
    if (dir.isEmpty) continue;
    if (File('$dir${Platform.pathSeparator}$exe').existsSync()) return true;
  }
  return false;
}
