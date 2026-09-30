// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/services/engines/verible/builtin_rule_profiles.dart';
import 'package:lintcrux/services/engines/verible/verible_engine.dart';

import '../fake_process_runner.dart';

const _jsonLine =
    '{"path":"top.sv","line":42,"column":13,"severity":"warning","rule":"no-tabs","message":"Use spaces instead of tabs"}';

void main() {
  group('VeribleEngine', () {
    test('identifies itself with engine id and display name', () {
      final engine = VeribleEngine();
      expect(engine.id, 'verible');
      expect(engine.displayName, 'Verible');
    });

    test('capabilities advertise structured output + config file support', () {
      final engine = VeribleEngine();
      expect(engine.capabilities.emitsStructuredOutput, isTrue);
      expect(engine.capabilities.supportsConfigFile, isTrue);
      expect(engine.capabilities.supportedLanguages, {
        HdlLanguage.verilog,
        HdlLanguage.systemVerilog,
      });
    });

    test('run streams parsed JSON-line violations', () async {
      final fake = FakeProcessRunner()..stdoutLines = <String>[_jsonLine];
      final engine = VeribleEngine(
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
      expect(violations.single.engineId, 'verible');
      expect(violations.single.ruleId, 'verible/no-tabs');
      expect(violations.single.severity, Severity.warning);
    });

    test(
      'run invokes verible-verilog-lint with --lint_output=jsonline',
      () async {
        final fake = FakeProcessRunner();
        final engine = VeribleEngine(runner: fake);
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
        expect(inv.executable, 'verible-verilog-lint');
        expect(inv.arguments, contains('--lint_output=jsonline'));
        expect(inv.arguments, contains('/x/a.sv'));
      },
    );

    test('text-mode fallback omits --lint_output=jsonline and parses '
        'text format', () async {
      final fake = FakeProcessRunner()
        ..stdoutLines = <String>[
          'top.sv:1:1: warning: msg [no-tabs]',
        ];
      final engine = VeribleEngine(runner: fake);
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
      expect(violations.single.ruleId, 'verible/no-tabs');
      expect(
        fake.invocations.single.arguments,
        isNot(contains('--lint_output=jsonline')),
      );
    });

    // ── Beta regression: the silent false-clean ──────────────────────
    //
    // `--lint_output=jsonline` is not an upstream flag. A stock
    // `verible-verilog-lint` answers `ERROR: unknown command line flag`,
    // prints usage, and exits non-zero having linted nothing — and the
    // engine used to report "Completed with 0 violations" on a file the
    // same binary flags 2,365 times.
    group('upstream flag rejection', () {
      test('retries in text mode automatically and parses the retry', () async {
        final fake = FakeProcessRunner()
          ..scripts.addAll(const <FakeRunScript>[
            // Attempt 1: upstream rejects the flag on stderr.
            FakeRunScript(
              stderr: <String>[
                "ERROR: unknown command line flag 'lint_output'",
                'Try --helpfull to get a list of all flags.',
              ],
              exitCode: 1,
            ),
            // Attempt 2 (text mode): real upstream output, on stderr,
            // with column ranges.
            FakeRunScript(
              stderr: <String>[
                'top.sv:8:24-42: Line length exceeds max: 100; is: 118 [line-length]',
                'top.sv:12:1-8: Use spaces, not tabs. [Style: tabs] [no-tabs]',
              ],
              exitCode: 1,
            ),
          ]);
        final engine = VeribleEngine(runner: fake, projectRoot: '/work');
        final violations = await engine
            .run(
              const LintRunRequest(
                sourceFiles: ['/work/top.sv'],
                binary: EngineBinaryConfig.system(),
                language: HdlLanguage.systemVerilog,
              ),
            )
            .toList();

        expect(fake.invocations, hasLength(2));
        expect(
          fake.invocations.first.arguments,
          contains('--lint_output=jsonline'),
        );
        expect(
          fake.invocations.last.arguments,
          isNot(contains('--lint_output=jsonline')),
          reason: 'the retry must drop the rejected flag',
        );
        expect(violations, hasLength(2));
        expect(violations.first.ruleId, 'verible/line-length');
        expect(violations.last.ruleId, 'verible/no-tabs');
      });

      test('a rejected flag on stdout also triggers the retry', () async {
        final fake = FakeProcessRunner()
          ..scripts.addAll(const <FakeRunScript>[
            FakeRunScript(
              stdout: <String>[
                "ERROR: Unknown command line flag 'lint_output'",
              ],
              exitCode: 1,
            ),
            FakeRunScript(
              stderr: <String>['top.sv:1:1-4: msg [no-tabs]'],
              exitCode: 1,
            ),
          ]);
        final engine = VeribleEngine(runner: fake, projectRoot: '/work');
        final violations = await engine
            .run(
              const LintRunRequest(
                sourceFiles: ['/work/top.sv'],
                binary: EngineBinaryConfig.system(),
                language: HdlLanguage.systemVerilog,
              ),
            )
            .toList();
        expect(fake.invocations, hasLength(2));
        expect(violations, hasLength(1));
      });

      test(
        'the retry is skipped when text mode was requested up front',
        () async {
          final fake = FakeProcessRunner()
            ..stderrLines = <String>['top.sv:1:1-4: msg [no-tabs]']
            ..exitCode = 1;
          final engine = VeribleEngine(runner: fake, projectRoot: '/work');
          final violations = await engine
              .run(
                const LintRunRequest(
                  sourceFiles: ['/work/top.sv'],
                  binary: EngineBinaryConfig.system(),
                  language: HdlLanguage.systemVerilog,
                  options: {'textModeFallback': true},
                ),
              )
              .toList();
          expect(fake.invocations, hasLength(1));
          expect(violations, hasLength(1));
        },
      );
    });

    // The contract that closes the whole silent-false-clean class, not
    // just the Verible instance of it.
    group('non-zero exit contract', () {
      test('errors OR yields violations when the binary exits non-zero '
          'with output', () async {
        // Case A — non-zero + output that parses: violations, no error.
        // `verible-verilog-lint` exits 1 precisely BECAUSE it found
        // findings, so a non-zero exit is not itself a failure.
        final ok = FakeProcessRunner()
          ..stderrLines = <String>['top.sv:1:1-4: msg [no-tabs]']
          ..exitCode = 1;
        final okViolations =
            await VeribleEngine(
                  runner: ok,
                  projectRoot: '/work',
                )
                .run(
                  const LintRunRequest(
                    sourceFiles: ['/work/top.sv'],
                    binary: EngineBinaryConfig.system(),
                    language: HdlLanguage.systemVerilog,
                    options: {'textModeFallback': true},
                  ),
                )
                .toList();
        expect(okViolations, isNotEmpty);

        // Case B — non-zero + output that parses to nothing: MUST error.
        // Reporting "Completed, 0 violations" here can green-light a
        // dirty design.
        final bad = FakeProcessRunner()
          ..stderrLines = <String>[
            'top.sv:1: syntax error at token "endmodule"',
            'Failed to parse.',
          ]
          ..exitCode = 2;
        await expectLater(
          VeribleEngine(runner: bad, projectRoot: '/work')
              .run(
                const LintRunRequest(
                  sourceFiles: ['/work/top.sv'],
                  binary: EngineBinaryConfig.system(),
                  language: HdlLanguage.systemVerilog,
                  options: {'textModeFallback': true},
                ),
              )
              .toList(),
          throwsA(
            isA<EngineRunFailedException>()
                .having((e) => e.engineId, 'engineId', 'verible')
                .having((e) => e.exitCode, 'exitCode', 2)
                .having(
                  (e) => e.outputExcerpt.join('\n'),
                  'outputExcerpt',
                  contains('syntax error'),
                ),
          ),
        );
      });

      test('a rejected flag that survives the retry surfaces an engine '
          'error, never a clean run', () async {
        final fake = FakeProcessRunner()
          ..stderrLines = <String>[
            "ERROR: unknown command line flag 'lint_output'",
          ]
          ..exitCode = 1;
        await expectLater(
          VeribleEngine(runner: fake, projectRoot: '/work')
              .run(
                const LintRunRequest(
                  sourceFiles: ['/work/top.sv'],
                  binary: EngineBinaryConfig.system(),
                  language: HdlLanguage.systemVerilog,
                ),
              )
              .toList(),
          throwsA(isA<EngineRunFailedException>()),
        );
        expect(fake.invocations, hasLength(2));
      });

      test('non-zero exit with no output at all still errors', () async {
        final fake = FakeProcessRunner()..exitCode = 137;
        await expectLater(
          VeribleEngine(runner: fake, projectRoot: '/work')
              .run(
                const LintRunRequest(
                  sourceFiles: ['/work/top.sv'],
                  binary: EngineBinaryConfig.system(),
                  language: HdlLanguage.systemVerilog,
                  options: {'textModeFallback': true},
                ),
              )
              .toList(),
          throwsA(
            isA<EngineRunFailedException>().having(
              (e) => e.reason,
              'reason',
              contains('no output'),
            ),
          ),
        );
      });

      test('a clean exit-0 run with no output is NOT an error', () async {
        final fake = FakeProcessRunner();
        final violations = await VeribleEngine(runner: fake)
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
    });

    test('stderr violations are parsed, not discarded', () async {
      // Upstream writes text-mode diagnostics to stderr; the engine used
      // to drain stderr into a black hole and parse only stdout.
      final fake = FakeProcessRunner()
        ..stderrLines = <String>['top.sv:4:9-20: msg [no-tabs]']
        ..exitCode = 1;
      final violations = await VeribleEngine(runner: fake, projectRoot: '/work')
          .run(
            const LintRunRequest(
              sourceFiles: ['/work/top.sv'],
              binary: EngineBinaryConfig.system(),
              language: HdlLanguage.systemVerilog,
              options: {'textModeFallback': true},
            ),
          )
          .toList();
      expect(violations, hasLength(1));
      expect(violations.single.location.file, '/work/top.sv');
      expect(violations.single.location.line, 4);
      expect(violations.single.location.column, 9);
    });

    test('ruleProfile option contributes --ruleset and --rules', () async {
      final fake = FakeProcessRunner();
      final engine = VeribleEngine(runner: fake);
      await engine
          .run(
            const LintRunRequest(
              sourceFiles: ['/x/a.sv'],
              binary: EngineBinaryConfig.system(),
              language: HdlLanguage.systemVerilog,
              options: {kVeribleRuleProfileOptionKey: 'lowrisc'},
            ),
          )
          .toList();
      final args = fake.invocations.single.arguments;
      expect(args, contains('--ruleset=none'));
      final rulesArg = args.firstWhere((a) => a.startsWith('--rules='));
      expect(rulesArg, contains('no-tabs'));
      expect(rulesArg, contains('line-length=length:100'));
      expect(rulesArg, isNot(contains('typedef-structs-unions')));
      // Rule selection must precede the file list and the power-user
      // escape hatch.
      expect(args.indexOf(rulesArg), lessThan(args.indexOf('/x/a.sv')));
    });

    test('ruleProfile args come before extraArgs so power users win', () async {
      final fake = FakeProcessRunner();
      final engine = VeribleEngine(runner: fake);
      await engine
          .run(
            const LintRunRequest(
              sourceFiles: ['/x/a.sv'],
              binary: EngineBinaryConfig.system(extraArgs: ['--ruleset=all']),
              language: HdlLanguage.systemVerilog,
              options: {kVeribleRuleProfileOptionKey: 'lowrisc'},
            ),
          )
          .toList();
      final args = fake.invocations.single.arguments;
      expect(
        args.indexOf('--ruleset=none'),
        lessThan(args.indexOf('--ruleset=all')),
      );
    });

    test('no rule-selection flags are added without a ruleProfile', () async {
      final fake = FakeProcessRunner();
      final engine = VeribleEngine(runner: fake);
      await engine
          .run(
            const LintRunRequest(
              sourceFiles: ['/x/a.sv'],
              binary: EngineBinaryConfig.system(),
              language: HdlLanguage.systemVerilog,
            ),
          )
          .toList();
      final args = fake.invocations.single.arguments;
      expect(args.any((a) => a.startsWith('--rules=')), isFalse);
      expect(args.any((a) => a.startsWith('--ruleset=')), isFalse);
    });

    test('an unknown ruleProfile fails the run instead of linting against '
        'an unintended rule set', () async {
      final fake = FakeProcessRunner();
      final engine = VeribleEngine(runner: fake);
      await expectLater(
        engine.run(
          const LintRunRequest(
            sourceFiles: ['/x/a.sv'],
            binary: EngineBinaryConfig.system(),
            language: HdlLanguage.systemVerilog,
            options: {kVeribleRuleProfileOptionKey: 'lowrsic'},
          ),
        ),
        emitsError(
          isA<EngineRunFailedException>().having(
            (e) => e.reason,
            'reason',
            allOf(contains('lowrsic'), contains('lowrisc')),
          ),
        ),
      );
      expect(fake.invocations, isEmpty);
    });

    test('a non-string ruleProfile fails the run', () async {
      final fake = FakeProcessRunner();
      final engine = VeribleEngine(runner: fake);
      await expectLater(
        engine.run(
          const LintRunRequest(
            sourceFiles: ['/x/a.sv'],
            binary: EngineBinaryConfig.system(),
            language: HdlLanguage.systemVerilog,
            options: {kVeribleRuleProfileOptionKey: true},
          ),
        ),
        emitsError(isA<EngineRunFailedException>()),
      );
      expect(fake.invocations, isEmpty);
    });

    test('--rules_config_search is added when option is set', () async {
      final fake = FakeProcessRunner();
      final engine = VeribleEngine(runner: fake);
      await engine
          .run(
            const LintRunRequest(
              sourceFiles: ['/x/a.sv'],
              binary: EngineBinaryConfig.system(),
              language: HdlLanguage.systemVerilog,
              options: {'rulesConfigSearch': true},
            ),
          )
          .toList();
      expect(
        fake.invocations.single.arguments,
        contains('--rules_config_search'),
      );
    });

    test('--rules_config_search is added when .rules.verible_lint exists '
        'in the project root', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'lintcrux_verible_config_test_',
      );
      try {
        await File('${tempDir.path}/.rules.verible_lint').writeAsString('');
        final fake = FakeProcessRunner();
        final engine = VeribleEngine(runner: fake, projectRoot: tempDir.path);
        await engine
            .run(
              LintRunRequest(
                sourceFiles: ['${tempDir.path}/a.sv'],
                binary: const EngineBinaryConfig.system(),
                language: HdlLanguage.systemVerilog,
              ),
            )
            .toList();
        expect(
          fake.invocations.single.arguments,
          contains('--rules_config_search'),
        );
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      '--rules_config_search is omitted when no config file exists',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'lintcrux_verible_noconfig_test_',
        );
        try {
          final fake = FakeProcessRunner();
          final engine = VeribleEngine(runner: fake, projectRoot: tempDir.path);
          await engine
              .run(
                LintRunRequest(
                  sourceFiles: ['${tempDir.path}/a.sv'],
                  binary: const EngineBinaryConfig.system(),
                  language: HdlLanguage.systemVerilog,
                ),
              )
              .toList();
          expect(
            fake.invocations.single.arguments,
            isNot(contains('--rules_config_search')),
          );
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );

    test('custom binary path is honored', () async {
      final fake = FakeProcessRunner();
      final engine = VeribleEngine(runner: fake);
      await engine
          .run(
            const LintRunRequest(
              sourceFiles: ['/x/a.sv'],
              binary: EngineBinaryConfig(
                source: EngineBinarySource.custom,
                path: '/opt/verible/bin/verible-verilog-lint',
              ),
              language: HdlLanguage.systemVerilog,
            ),
          )
          .toList();
      expect(
        fake.invocations.single.executable,
        '/opt/verible/bin/verible-verilog-lint',
      );
    });

    test('run throws EngineNotAvailableException when binary cannot be '
        'launched', () async {
      final fake = FakeProcessRunner()
        ..onStartThrows = const ProcessException(
          'verible-verilog-lint',
          [],
          'No such file or directory',
        );
      final engine = VeribleEngine(runner: fake);
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
            'verible',
          ),
        ),
      );
    });

    test('cancel kills an in-progress subprocess', () async {
      final fake = FakeProcessRunner()
        ..holdOpen = true
        ..stdoutLines = <String>[_jsonLine];
      final engine = VeribleEngine(runner: fake);
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
      VeribleEngine(runner: FakeProcessRunner()).cancel();
    });

    test('detectVersion returns the trimmed first non-empty line', () async {
      final fake = FakeProcessRunner()
        ..stdoutLines = const <String>['v0.0-3624-g8fab30b'];
      final engine = VeribleEngine(runner: fake);
      final version = await engine.detectVersion(
        const EngineBinaryConfig.system(),
      );
      expect(version, 'v0.0-3624-g8fab30b');
    });

    test(
      'detectVersion returns null when the subprocess exits non-zero',
      () async {
        final fake = FakeProcessRunner()..exitCode = 1;
        final engine = VeribleEngine(runner: fake);
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
          ..onStartThrows = const ProcessException('verible-verilog-lint', []);
        final engine = VeribleEngine(runner: fake);
        final version = await engine.detectVersion(
          const EngineBinaryConfig.system(),
        );
        expect(version, isNull);
      },
    );
  });

  group('VeribleEngine integration with real binary', () {
    test(
      'detectVersion against system verible-verilog-lint',
      () async {
        final engine = VeribleEngine();
        final version = await engine.detectVersion(
          const EngineBinaryConfig.system(),
        );
        expect(version, isNotNull);
        expect(version!.trim(), isNotEmpty);
      },
      skip: _veribleOnPath() ? false : 'verible-verilog-lint not on PATH',
    );
  });

  group('VeribleEngine project root', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('lintcrux_verible_root_');
      File(
        '${root.path}/.rules.verible_lint',
      ).writeAsStringSync('-line-length\n');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('a root .rules.verible_lint turns on --rules_config_search', () async {
      // Constructed the way the registry builds it — with no root.
      final fake = FakeProcessRunner();
      await VeribleEngine(runner: fake)
          .run(
            LintRunRequest(
              sourceFiles: ['${root.path}/rtl/top.sv'],
              binary: const EngineBinaryConfig.system(),
              language: HdlLanguage.systemVerilog,
              projectRoot: root.path,
              options: const <String, Object?>{'textModeFallback': true},
            ),
          )
          .toList();
      expect(
        fake.invocations.first.arguments,
        contains('--rules_config_search'),
      );
    });

    test('no config file and no option leaves the search off', () async {
      final fake = FakeProcessRunner();
      await VeribleEngine(runner: fake)
          .run(
            const LintRunRequest(
              sourceFiles: ['/elsewhere/top.sv'],
              binary: EngineBinaryConfig.system(),
              language: HdlLanguage.systemVerilog,
              projectRoot: '/nonexistent/project',
              options: <String, Object?>{'textModeFallback': true},
            ),
          )
          .toList();
      expect(
        fake.invocations.first.arguments,
        isNot(contains('--rules_config_search')),
      );
    });
  });
}

bool _veribleOnPath() {
  final pathVar = Platform.environment['PATH'] ?? '';
  final exe = Platform.isWindows
      ? 'verible-verilog-lint.exe'
      : 'verible-verilog-lint';
  for (final dir in pathVar.split(Platform.isWindows ? ';' : ':')) {
    if (dir.isEmpty) continue;
    if (File('$dir${Platform.pathSeparator}$exe').existsSync()) return true;
  }
  return false;
}
