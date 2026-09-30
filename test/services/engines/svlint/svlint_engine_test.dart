// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/services/engines/svlint/svlint_engine.dart';

import '../fake_process_runner.dart';

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
      expect(engine.capabilities.emitsStructuredOutput, isTrue);
      expect(engine.capabilities.supportsConfigFile, isTrue);
    });

    test('run streams parsed violations from stdout JSON', () async {
      const jsonLine =
          '{"path":"top.sv","line":4,"column":2,"rule":"non_blocking_assignment_in_always_comb","message":"m"}';
      final fake = FakeProcessRunner()..stdoutLines = const [jsonLine];
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
    });

    test('run invokes svlint with --output-format json + sources', () async {
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
      expect(inv.arguments, containsAllInOrder(['--output-format', 'json']));
      expect(inv.arguments, containsAllInOrder(['/x/a.sv', '/x/b.sv']));
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

    test('textModeFallback option skips --output-format json', () async {
      final fake = FakeProcessRunner();
      final engine = SvlintEngine(runner: fake);
      await engine
          .run(
            const LintRunRequest(
              sourceFiles: ['/x/a.sv'],
              binary: EngineBinaryConfig.system(),
              language: HdlLanguage.systemVerilog,
              options: {'textModeFallback': true},
            ),
          )
          .toList();
      final args = fake.invocations.single.arguments;
      expect(args, isNot(contains('--output-format')));
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
            ['--output-format', 'json'],
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
      final fake = FakeProcessRunner()..holdOpen = true;
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
      skip: _svlintOnPath() ? false : 'svlint not on PATH',
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
