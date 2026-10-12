// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/services/engines/svlint/svlint_engine.dart';

import '../fake_process_runner.dart';

/// One finding as svlint prints it with no output flag.
const List<String> _failBlock = <String>[
  'Fail: non_blocking_assignment_in_always_comb',
  '   --> top.sv:7:3',
  '  |',
  '7 |   always_comb begin',
  '  |   ^^^^^^^^^^^ hint  : Remove non-blocking assignment in `always_comb`.',
  '  |               reason: Scheduling between blocking and non-blocking assignments is non-deterministic.',
  '',
];

void main() {
  group('SvlintEngine', () {
    test('identifies itself with the engine id and display name', () {
      final engine = SvlintEngine();
      expect(engine.id, 'svlint');
      expect(engine.displayName, 'Svlint');
    });

    test('declares SystemVerilog + Verilog support', () {
      final engine = SvlintEngine();
      expect(
        engine.capabilities.supportedLanguages,
        {HdlLanguage.systemVerilog, HdlLanguage.verilog},
      );
      // Svlint has no JSON mode; the engine parses its default report.
      expect(engine.capabilities.emitsStructuredOutput, isFalse);
      expect(engine.capabilities.supportsConfigFile, isTrue);
    });

    test('run streams parsed violations from the default report', () async {
      // Exit 1 is how svlint says "a rule failed"; it is not a failure.
      final fake = FakeProcessRunner()
        ..stdoutLines = _failBlock
        ..exitCode = 1;
      final engine = SvlintEngine(
        runner: fake,
        projectRoot: '/work/sv',
      );
      final violations = await engine
          .run(
            const LintRunRequest(
              sourceFiles: ['/work/sv/top.sv'],
              binary: EngineBinaryConfig.system(),
              language: HdlLanguage.systemVerilog,
            ),
          )
          .toList();
      expect(violations, hasLength(1));
      expect(
        violations.single.ruleId,
        'svlint/non_blocking_assignment_in_always_comb',
      );
      expect(violations.single.location.file, '/work/sv/top.sv');
      expect(violations.single.location.line, 7);
    });

    test('run invokes svlint with the sources and no output flag', () async {
      // `--output-format` is not an svlint option: svlint exits 2 on it and
      // lints nothing, which is how every run came back clean.
      final fake = FakeProcessRunner();
      final engine = SvlintEngine(runner: fake);
      await engine
          .run(
            const LintRunRequest(
              sourceFiles: ['/x/a.sv', '/x/b.sv'],
              binary: EngineBinaryConfig.system(),
              language: HdlLanguage.systemVerilog,
            ),
          )
          .toList();
      final inv = fake.invocations.single;
      expect(inv.executable, 'svlint');
      expect(inv.arguments, isNot(contains('--output-format')));
      expect(inv.arguments, isNot(contains('json')));
      expect(inv.arguments, containsAllInOrder(['/x/a.sv', '/x/b.sv']));
    });

    test('a clean run exits 0 and yields nothing', () async {
      final fake = FakeProcessRunner();
      final violations = await SvlintEngine(runner: fake)
          .run(
            const LintRunRequest(
              sourceFiles: ['/x/a.sv'],
              binary: EngineBinaryConfig.system(),
              language: HdlLanguage.systemVerilog,
            ),
          )
          .toList();
      expect(violations, isEmpty);
    });

    test(
      'a non-zero exit with no finding is an engine failure, not a clean run',
      () async {
        // What svlint prints for an option it does not know (exit 2).
        final fake = FakeProcessRunner()
          ..stderrLines = const <String>[
            "error: Found argument '--output-format' which wasn't expected, or isn't valid in this context",
            '',
            'USAGE:',
            '    svlint [OPTIONS] [--] [FILES]...',
          ]
          ..exitCode = 2;
        await expectLater(
          SvlintEngine(runner: fake)
              .run(
                const LintRunRequest(
                  sourceFiles: ['/x/a.sv'],
                  binary: EngineBinaryConfig.system(),
                  language: HdlLanguage.systemVerilog,
                ),
              )
              .toList(),
          throwsA(
            isA<EngineRunFailedException>()
                .having((e) => e.engineId, 'engineId', 'svlint')
                .having((e) => e.exitCode, 'exitCode', 2)
                .having(
                  (e) => e.reason,
                  'reason',
                  startsWith("error: Found argument '--output-format'"),
                ),
          ),
        );
      },
    );

    test('a missing source file is an engine failure', () async {
      final fake = FakeProcessRunner()
        ..stdoutLines = const <String>[
          'Error: No such file or directory (os error 2)',
        ]
        ..exitCode = 2;
      await expectLater(
        SvlintEngine(runner: fake)
            .run(
              const LintRunRequest(
                sourceFiles: ['/x/missing.sv'],
                binary: EngineBinaryConfig.system(),
                language: HdlLanguage.systemVerilog,
              ),
            )
            .toList(),
        throwsA(
          isA<EngineRunFailedException>().having(
            (e) => e.reason,
            'reason',
            'Error: No such file or directory (os error 2)',
          ),
        ),
      );
    });

    test('a non-zero exit with no output names the exit code', () async {
      final fake = FakeProcessRunner()..exitCode = 101;
      await expectLater(
        SvlintEngine(runner: fake)
            .run(
              const LintRunRequest(
                sourceFiles: ['/x/a.sv'],
                binary: EngineBinaryConfig.system(),
                language: HdlLanguage.systemVerilog,
              ),
            )
            .toList(),
        throwsA(
          isA<EngineRunFailedException>().having(
            (e) => e.reason,
            'reason',
            'exited 101 with no output',
          ),
        ),
      );
    });

    test(
      'explicit configPath option overrides .svlint.toml detection',
      () async {
        final fake = FakeProcessRunner();
        final engine = SvlintEngine(runner: fake);
        await engine
            .run(
              const LintRunRequest(
                sourceFiles: ['/x/a.sv'],
                binary: EngineBinaryConfig.system(),
                language: HdlLanguage.systemVerilog,
                options: {'configPath': '/x/custom-svlint.toml'},
              ),
            )
            .toList();
        final args = fake.invocations.single.arguments;
        expect(
          args,
          containsAllInOrder(['--config', '/x/custom-svlint.toml']),
        );
      },
    );

    test('.svlint.toml at project root is auto-picked-up', () async {
      final dir = Directory.systemTemp.createTempSync('svlint-engine-');
      try {
        File('${dir.path}/.svlint.toml').writeAsStringSync('# test fixture\n');
        final fake = FakeProcessRunner();
        final engine = SvlintEngine(
          runner: fake,
          projectRoot: dir.path,
        );
        await engine
            .run(
              LintRunRequest(
                sourceFiles: ['${dir.path}/a.sv'],
                binary: const EngineBinaryConfig.system(),
                language: HdlLanguage.systemVerilog,
              ),
            )
            .toList();
        final args = fake.invocations.single.arguments;
        expect(args, contains('--config'));
        // The .svlint.toml path should be present somewhere in the
        // argument list right after --config.
        final idx = args.indexOf('--config');
        expect(args[idx + 1], endsWith('.svlint.toml'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('custom binary path is honored', () async {
      final fake = FakeProcessRunner();
      final engine = SvlintEngine(runner: fake);
      await engine
          .run(
            const LintRunRequest(
              sourceFiles: ['/x/a.sv'],
              binary: EngineBinaryConfig(
                source: EngineBinarySource.custom,
                path: '/opt/svlint-0.9.3/svlint',
              ),
              language: HdlLanguage.systemVerilog,
            ),
          )
          .toList();
      expect(
        fake.invocations.single.executable,
        '/opt/svlint-0.9.3/svlint',
      );
    });

    test(
      'throws EngineNotAvailableException when binary cannot be launched',
      () async {
        final fake = FakeProcessRunner()
          ..onStartThrows = const ProcessException(
            'svlint',
            ['/x/a.sv'],
            'No such file or directory',
          );
        final engine = SvlintEngine(runner: fake);
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
              'svlint',
            ),
          ),
        );
      },
    );

    test('cancel kills an in-progress subprocess', () async {
      final fake = FakeProcessRunner()
        ..holdOpen = true
        ..stdoutLines = _failBlock;
      final engine = SvlintEngine(runner: fake);
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

    test('cancel before run is a no-op (does not crash)', () {
      SvlintEngine(runner: FakeProcessRunner()).cancel();
    });

    test('detectVersion returns the trimmed first non-empty line', () async {
      final fake = FakeProcessRunner()..stdoutLines = const ['svlint 0.9.3'];
      final engine = SvlintEngine(runner: fake);
      final version = await engine.detectVersion(
        const EngineBinaryConfig.system(),
      );
      expect(version, 'svlint 0.9.3');
    });

    test('detectVersion returns null on subprocess error', () async {
      final fake = FakeProcessRunner()..exitCode = 1;
      final engine = SvlintEngine(runner: fake);
      final version = await engine.detectVersion(
        const EngineBinaryConfig.system(),
      );
      expect(version, isNull);
    });
  });

  group('SvlintEngine integration with real binary', () {
    final skip = _svlintOnPath() ? false : 'svlint not on PATH';

    test(
      'detectVersion against system svlint',
      () async {
        final engine = SvlintEngine();
        final version = await engine.detectVersion(
          const EngineBinaryConfig.system(),
        );
        expect(version, isNotNull);
        expect(version!.trim(), isNotEmpty);
      },
      skip: skip,
    );

    // The unit tests above run on canned output. This is the one test that
    // exercises the real invocation end to end, so a flag svlint rejects, or
    // a report shape it no longer prints, fails here rather than as a clean
    // run on a user's machine.
    test(
      'lints a file with a known violation and reports it',
      () async {
        final dir = Directory.systemTemp.createTempSync('svlint-real-');
        try {
          // A config of our own so the finding set does not depend on the
          // rules a future svlint enables by default.
          File('${dir.path}/.svlint.toml').writeAsStringSync(
            '[option]\n\n[textrules]\n\n[syntaxrules]\n'
            'blocking_assignment_in_always_ff = true\n',
          );
          final source = File('${dir.path}/top.sv')
            ..writeAsStringSync(
              'module top (input logic clk, output logic q);\n'
              '  always_ff @(posedge clk) begin\n'
              '    q = ~q;\n'
              '  end\n'
              'endmodule\n',
            );
          final violations = await SvlintEngine(projectRoot: dir.path)
              .run(
                LintRunRequest(
                  sourceFiles: <String>[source.path],
                  binary: const EngineBinaryConfig.system(),
                  language: HdlLanguage.systemVerilog,
                  projectRoot: dir.path,
                ),
              )
              .toList();
          expect(violations, hasLength(1));
          expect(
            violations.single.ruleId,
            'svlint/blocking_assignment_in_always_ff',
          );
          expect(violations.single.location.file, source.path);
          expect(violations.single.location.line, 2);
          expect(violations.single.message, isNotEmpty);
        } finally {
          dir.deleteSync(recursive: true);
        }
      },
      skip: skip,
    );

    test(
      'a source svlint cannot open is an engine failure',
      () async {
        final dir = Directory.systemTemp.createTempSync('svlint-real-');
        try {
          File('${dir.path}/.svlint.toml').writeAsStringSync('[option]\n');
          await expectLater(
            SvlintEngine(projectRoot: dir.path)
                .run(
                  LintRunRequest(
                    sourceFiles: <String>['${dir.path}/does_not_exist.sv'],
                    binary: const EngineBinaryConfig.system(),
                    language: HdlLanguage.systemVerilog,
                    projectRoot: dir.path,
                  ),
                )
                .toList(),
            throwsA(isA<EngineRunFailedException>()),
          );
        } finally {
          dir.deleteSync(recursive: true);
        }
      },
      skip: skip,
    );
  });

  group('SvlintEngine project root', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('lintcrux_svlint_root_');
      File('${root.path}/.svlint.toml').writeAsStringSync('[option]\n');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('a root .svlint.toml reaches a source outside the root', () async {
      // Constructed the way the registry builds it — with no root — so the
      // request's project root is what finds the config.
      final fake = FakeProcessRunner();
      await SvlintEngine(runner: fake)
          .run(
            LintRunRequest(
              sourceFiles: const ['/elsewhere/ip/fifo.sv'],
              binary: const EngineBinaryConfig.system(),
              language: HdlLanguage.systemVerilog,
              projectRoot: root.path,
            ),
          )
          .toList();
      expect(
        fake.invocations.single.arguments,
        containsAllInOrder(['--config', '${root.path}/.svlint.toml']),
      );
    });
  });
}

bool _svlintOnPath() {
  final pathVar = Platform.environment['PATH'] ?? '';
  final exe = Platform.isWindows ? 'svlint.exe' : 'svlint';
  for (final dir in pathVar.split(Platform.isWindows ? ';' : ':')) {
    if (dir.isEmpty) continue;
    if (File('$dir${Platform.pathSeparator}$exe').existsSync()) return true;
  }
  return false;
}
