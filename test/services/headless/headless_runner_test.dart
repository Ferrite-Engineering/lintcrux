// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart'
    show ProcessRunResult, ProcessRunner;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/cli/cli_args.dart';
import 'package:lintcrux/core/cli/cli_exit_codes.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/baseline_violation.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/lint_baseline.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/cdc/cdc_engine.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/yosys/yosys_check_engine.dart';
import 'package:lintcrux/services/headless/headless_runner.dart';
import 'package:path/path.dart' as p;

/// A [LintEngine] whose behavior is dictated by the test.
class _FakeEngine implements LintEngine {
  _FakeEngine(
    this.id, {
    this.violations = const <Violation>[],
    this.error,
    this.languages = const {HdlLanguage.systemVerilog, HdlLanguage.verilog},
  });

  @override
  final String id;
  final List<Violation> violations;
  final Object? error;
  final Set<HdlLanguage> languages;

  @override
  String get displayName => id;

  @override
  EngineCapabilities get capabilities =>
      EngineCapabilities(supportedLanguages: languages);

  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async => '1.0.0';

  @override
  Stream<Violation> run(LintRunRequest request) async* {
    final e = error;
    // The engine exceptions `implements Exception` rather than extending
    // it, so the analyzer cannot see that this is a legal throw.
    // ignore: only_throw_errors
    if (e != null) throw e;
    for (final v in violations) {
      yield v;
    }
  }

  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) => run(request);

  @override
  void cancel() {}
}

/// A Yosys process runner on a machine with no Yosys.
class _MissingBinaryProcessRunner implements ProcessRunner {
  final List<String> executables = <String>[];

  @override
  Future<ProcessRunResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    Future<void>? cancelSignal,
    String? stdoutFilePath,
    void Function(String line)? onStderrLine,
  }) async {
    executables.add(executable);
    throw ProcessException(executable, arguments, 'No such file or directory');
  }
}

void main() {
  late Directory tmp;
  late String projectPath;
  late String sourcePath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lintcrux_runner_');
    sourcePath = p.join(tmp.path, 'top.sv');
    File(sourcePath).writeAsStringSync('module top; endmodule\n');
    projectPath = p.join(tmp.path, 'design.lintcrux');
    File(projectPath).writeAsStringSync(
      jsonEncode(<String, Object?>{
        'version': 1,
        'name': 'design',
        'rootPath': '.',
        'sourceFiles': <String>['top.sv'],
        'language': 'systemverilog',
      }),
    );
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Violation violation({
    String rule = 'fake/RULE',
    Severity severity = Severity.warning,
    int line = 1,
    String message = 'a finding',
    String? file,
    String engineId = 'fake',
  }) {
    return Violation(
      engineId: engineId,
      ruleId: rule,
      severity: severity,
      message: message,
      location: SourceLocation(file: file ?? sourcePath, line: line, column: 1),
    );
  }

  HeadlessRunner runnerWith(List<LintEngine> engines) =>
      HeadlessRunner(registry: EngineRegistry(engines));

  CliArgs args({
    bool exitCode = false,
    bool failOnNew = false,
    bool allowMissing = false,
    int? ciGateThreshold,
    String? baseline,
    String? config,
    String? exportFormat,
    String? out,
    List<String> engines = const <String>[],
  }) {
    return CliArgs(
      paths: <String>[projectPath],
      exitCodeOnFindings: exitCode,
      failOnNewViolations: failOnNew,
      allowMissingEngines: allowMissing,
      ciGateThreshold: ciGateThreshold,
      baselinePath: baseline,
      configPath: config,
      exportFormat: exportFormat,
      exportOutputPath: out,
      engineIds: engines,
    );
  }

  group('exit-code contract', () {
    test('violations present but no gate requested → clean (0)', () async {
      final r = await runnerWith([
        _FakeEngine('fake', violations: [violation()]),
      ]).run(args());
      expect(r.exitCode, CliExitCode.clean);
      expect(r.reportableViolations, hasLength(1));
    });

    test('no violations with --exit-code → clean (0)', () async {
      final r = await runnerWith([_FakeEngine('fake')]).run(
        args(exitCode: true),
      );
      expect(r.exitCode, CliExitCode.clean);
    });

    test('violations with --exit-code → violations (1)', () async {
      final r = await runnerWith([
        _FakeEngine('fake', violations: [violation()]),
      ]).run(args(exitCode: true));
      expect(r.exitCode, CliExitCode.violations);
    });

    test('an engine that fails → runFailed (3)', () async {
      final r = await runnerWith([
        _FakeEngine(
          'fake',
          error: const EngineRunFailedException(
            engineId: 'fake',
            exitCode: 1,
            reason: 'rejected a flag',
          ),
        ),
      ]).run(args(exitCode: true));
      expect(r.exitCode, CliExitCode.runFailed);
      expect(r.problems.single, contains('rejected a flag'));
    });

    test(
      'run failure outranks violations — a partial run is not a count',
      () async {
        // The whole reason this layer exists: reporting "0 violations"
        // from a run where an engine died is the silent-false-clean
        // defect. A run that both found violations AND had an engine
        // fail must report the failure.
        final r = await runnerWith([
          _FakeEngine('good', violations: [violation(engineId: 'good')]),
          _FakeEngine(
            'bad',
            error: const EngineRunFailedException(
              engineId: 'bad',
              exitCode: 2,
              reason: 'boom',
            ),
          ),
        ]).run(args(exitCode: true, failOnNew: true));
        expect(r.exitCode, CliExitCode.runFailed);
      },
    );

    test('a missing engine binary → runFailed (3) by default', () async {
      final r = await runnerWith([
        _FakeEngine(
          'fake',
          error: const EngineNotAvailableException(
            engineId: 'fake',
            reason: 'not on PATH',
          ),
        ),
      ]).run(args());
      expect(r.exitCode, CliExitCode.runFailed);
      expect(r.problems.single, contains('unavailable'));
      expect(
        r.problems.single,
        contains('--allow-missing-engines'),
        reason: 'the error must name the escape hatch',
      );
    });

    test('--allow-missing-engines downgrades it to a diagnostic', () async {
      final r = await runnerWith([
        _FakeEngine(
          'fake',
          error: const EngineNotAvailableException(
            engineId: 'fake',
            reason: 'not on PATH',
          ),
        ),
      ]).run(args(allowMissing: true));
      expect(r.exitCode, CliExitCode.clean);
      expect(r.problems, isEmpty);
      expect(r.diagnostics.single, contains('skipped'));
    });

    group('the Yosys-backed engines on a machine without yosys', () {
      test('yosys → runFailed (3), never a clean run', () async {
        final r = await runnerWith([
          YosysCheckEngine(processRunner: _MissingBinaryProcessRunner()),
        ]).run(args(exitCode: true));
        expect(r.exitCode, CliExitCode.runFailed);
        expect(r.problems.single, contains('"yosys" is unavailable'));
        expect(r.problems.single, contains('--yosys-path'));
      });

      test('cdc → runFailed (3), and the hint names --yosys-path', () async {
        final r = await runnerWith([
          CdcEngine(processRunner: _MissingBinaryProcessRunner()),
        ]).run(args());
        expect(r.exitCode, CliExitCode.runFailed);
        expect(r.violations, isEmpty);
        expect(r.problems.single, contains('"cdc" is unavailable'));
        expect(r.problems.single, contains('--yosys-path'));
        expect(
          r.problems.single,
          isNot(contains('--cdc-path')),
          reason:
              'there is no --cdc-path flag; following the hint was a '
              'usage error',
        );
      });

      test('--allow-missing-engines tolerates both', () async {
        final r = await runnerWith([
          YosysCheckEngine(processRunner: _MissingBinaryProcessRunner()),
          CdcEngine(processRunner: _MissingBinaryProcessRunner()),
        ]).run(args(allowMissing: true, exitCode: true));
        expect(r.exitCode, CliExitCode.clean);
        expect(r.problems, isEmpty);
        expect(
          r.diagnostics.where((d) => d.contains('skipped')),
          hasLength(2),
        );
      });

      test('--yosys-path reaches both engines', () async {
        final yosysRunner = _MissingBinaryProcessRunner();
        final cdcRunner = _MissingBinaryProcessRunner();
        await runnerWith([
          YosysCheckEngine(processRunner: yosysRunner),
          CdcEngine(processRunner: cdcRunner),
        ]).run(
          CliArgs(
            paths: <String>[projectPath],
            engineBinaryPaths: const <String, String>{
              'yosys': '/opt/y/bin/yosys',
            },
          ),
        );
        // The Yosys engine is cacheable, so its version probe spawns the
        // binary too — every spawn must be the configured one.
        for (final spawned in [
          yosysRunner.executables,
          cdcRunner.executables,
        ]) {
          expect(spawned, isNotEmpty);
          expect(spawned, everyElement('/opt/y/bin/yosys'));
        }
      });
    });

    test('an unknown --engine id → usage (64), not a narrower run', () async {
      final r = await runnerWith([_FakeEngine('fake')]).run(
        args(engines: <String>['fakee']),
      );
      expect(r.exitCode, CliExitCode.usage);
      expect(r.problems.single, contains('Unknown engine id'));
    });

    test('an unusable positional → usage (64)', () async {
      final r = await runnerWith([_FakeEngine('fake')]).run(
        const CliArgs(paths: <String>['notes.txt']),
      );
      expect(r.exitCode, CliExitCode.usage);
    });

    test('an unparseable project file → runFailed (3)', () async {
      // The command line named a project that exists; the input is broken,
      // not the pipeline.
      File(projectPath).writeAsStringSync('{ not json');
      final r = await runnerWith([_FakeEngine('fake')]).run(args());
      expect(r.exitCode, CliExitCode.runFailed);
    });

    test('a project listing a missing source → runFailed (3)', () async {
      File(sourcePath).deleteSync();
      final r = await runnerWith([_FakeEngine('fake')]).run(args());
      expect(r.exitCode, CliExitCode.runFailed);
      expect(r.problems.single, contains('missing'));
    });

    test('a project declaring no sources → runFailed (3)', () async {
      File(projectPath).writeAsStringSync(
        jsonEncode(<String, Object?>{
          'version': 1,
          'name': 'design',
          'rootPath': '.',
          'sourceFiles': <String>[],
        }),
      );
      final r = await runnerWith([_FakeEngine('fake')]).run(args());
      expect(r.exitCode, CliExitCode.runFailed);
    });

    test('a project path that does not exist → usage (64)', () async {
      final r = await runnerWith([_FakeEngine('fake')]).run(
        CliArgs(paths: <String>[p.join(tmp.path, 'typo.lintcrux')]),
      );
      expect(r.exitCode, CliExitCode.usage);
    });

    test('no engine with a compatible source → runFailed (3)', () async {
      // A VHDL-only engine against a SystemVerilog project. Zero engines
      // ran, so "0 violations" would be a lie of omission.
      final r = await runnerWith([
        _FakeEngine('ghdlish', languages: const {HdlLanguage.vhdl}),
      ]).run(args());
      expect(r.exitCode, CliExitCode.runFailed);
      expect(r.problems.single, contains('No engine had a compatible'));
    });
  });

  group('--fail-on-new-violations', () {
    void writeBaseline(List<Violation> frozen, {String? at}) {
      File(at ?? p.join(tmp.path, '.lintcrux-baseline.json')).writeAsStringSync(
        jsonEncode(
          LintBaseline(
            baselineId: 'test',
            createdAt: DateTime.utc(2026),
            projectPath: tmp.path,
            frozenViolations: <BaselineViolation>[
              for (final v in frozen)
                BaselineViolation.fromViolation(v, projectRoot: tmp.path),
            ],
          ).toJson(),
        ),
      );
    }

    test('a violation already in the baseline does not fail', () async {
      final v = violation();
      writeBaseline(<Violation>[v]);
      final r =
          await runnerWith([
            _FakeEngine('fake', violations: [v]),
          ]).run(
            args(failOnNew: true),
          );
      expect(r.exitCode, CliExitCode.clean);
      expect(r.newViolations, isEmpty);
      expect(r.persistingViolations, hasLength(1));
      expect(r.baselineApplied, isTrue);
    });

    test('a violation absent from the baseline fails with 2', () async {
      writeBaseline(<Violation>[violation(rule: 'fake/OLD')]);
      final r = await runnerWith([
        _FakeEngine(
          'fake',
          violations: [
            violation(rule: 'fake/OLD'),
            violation(rule: 'fake/NEW'),
          ],
        ),
      ]).run(args(failOnNew: true));
      expect(r.exitCode, CliExitCode.newViolations);
      expect(r.newViolations.single.ruleId, 'fake/NEW');
      expect(r.persistingViolations.single.ruleId, 'fake/OLD');
    });

    test('the fingerprint ignores line shifts', () async {
      // The point of fingerprinting on (rule, file, message) rather than
      // position: adding an import above a violation must not turn it
      // into a regression.
      writeBaseline(<Violation>[violation(line: 10)]);
      final r = await runnerWith([
        _FakeEngine('fake', violations: [violation(line: 42)]),
      ]).run(args(failOnNew: true));
      expect(r.exitCode, CliExitCode.clean);
      expect(r.newViolations, isEmpty);
    });

    test('a baseline entry no longer reported counts as resolved', () async {
      writeBaseline(<Violation>[
        violation(rule: 'fake/FIXED'),
        violation(rule: 'fake/STILL'),
      ]);
      final r = await runnerWith([
        _FakeEngine('fake', violations: [violation(rule: 'fake/STILL')]),
      ]).run(args(failOnNew: true));
      expect(r.resolvedViolationCount, 1);
      expect(r.exitCode, CliExitCode.clean);
    });

    test('new violations (2) outrank plain violations (1)', () async {
      writeBaseline(const <Violation>[]);
      final r = await runnerWith([
        _FakeEngine('fake', violations: [violation()]),
      ]).run(args(failOnNew: true, exitCode: true));
      expect(r.exitCode, CliExitCode.newViolations);
    });

    test('a missing baseline treats everything as new (strict)', () async {
      final r = await runnerWith([
        _FakeEngine('fake', violations: [violation()]),
      ]).run(args(failOnNew: true));
      expect(r.exitCode, CliExitCode.newViolations);
      expect(r.baselineApplied, isFalse);
      expect(r.diagnostics.join(), contains('no baseline'));
    });

    test('a corrupt baseline fails the run rather than passing', () async {
      final path = p.join(tmp.path, '.lintcrux-baseline.json');
      File(path).writeAsStringSync('{ not json');
      final r = await runnerWith([_FakeEngine('fake')]).run(
        args(failOnNew: true),
      );
      expect(r.exitCode, CliExitCode.runFailed);
      expect(r.problems.single, contains('could not read baseline'));
    });

    test(
      'a baseline recorded in another checkout gates this one (exit 0)',
      () async {
        // The desktop sets the baseline at the engineer's checkout; CI reads
        // it at the runner's. Only the project-relative path is compared.
        final elsewhere = p.join(p.dirname(tmp.path), 'alice', 'soc');
        final recorded = violation(file: p.join(elsewhere, 'top.sv'));
        File(p.join(tmp.path, '.lintcrux-baseline.json')).writeAsStringSync(
          jsonEncode(
            LintBaseline(
              baselineId: 'desktop',
              createdAt: DateTime.utc(2026),
              projectPath: elsewhere,
              frozenViolations: <BaselineViolation>[
                BaselineViolation.fromViolation(
                  recorded,
                  projectRoot: elsewhere,
                ),
              ],
            ).toJson(),
          ),
        );
        final r = await runnerWith([
          _FakeEngine('fake', violations: [violation()]),
        ]).run(args(failOnNew: true));
        expect(r.exitCode, CliExitCode.clean);
        expect(r.persistingViolations, hasLength(1));
      },
    );

    test('a version 1 baseline from another checkout still gates', () async {
      // Written by a build whose fingerprints hashed the absolute path: the
      // reader migrates it rather than turning every finding new.
      final elsewhere = p.join(p.dirname(tmp.path), 'alice', 'soc');
      final absolute = p.join(elsewhere, 'top.sv');
      File(p.join(tmp.path, '.lintcrux-baseline.json')).writeAsStringSync(
        jsonEncode(<String, Object?>{
          'version': 1,
          'baselineId': 'legacy',
          'createdAt': '2026-01-01T00:00:00.000Z',
          'projectPath': elsewhere,
          'frozenViolations': <Object?>[
            <String, Object?>{
              'fingerprint': BaselineFingerprint.compute(
                ruleId: 'fake/RULE',
                filePath: absolute,
                message: 'a finding',
              ),
              'ruleId': 'fake/RULE',
              'filePath': absolute,
              'line': 1,
              'message': 'a finding',
            },
          ],
        }),
      );
      final r = await runnerWith([
        _FakeEngine('fake', violations: [violation()]),
      ]).run(args(failOnNew: true));
      expect(r.exitCode, CliExitCode.clean);
    });

    test('--baseline points the gate at a different file', () async {
      final custom = p.join(tmp.path, 'ci-baseline.json');
      writeBaseline(<Violation>[violation()], at: custom);
      final r = await runnerWith([
        _FakeEngine('fake', violations: [violation()]),
      ]).run(args(failOnNew: true, baseline: custom));
      expect(r.baselinePath, custom);
      expect(r.exitCode, CliExitCode.clean);
    });
  });

  group('the organization ciGateThreshold', () {
    test(
      'no threshold gates nothing, however many violations there are',
      () async {
        final r = await runnerWith([
          _FakeEngine(
            'fake',
            violations: [
              violation(),
              violation(rule: 'b'),
            ],
          ),
        ]).run(args());
        expect(
          r.exitCode,
          CliExitCode.clean,
          reason: 'a bare run is a reporting command, not a gate',
        );
      },
    );

    test('at or under the ceiling is clean', () async {
      final r = await runnerWith([
        _FakeEngine(
          'fake',
          violations: [
            violation(),
            violation(rule: 'b'),
          ],
        ),
      ]).run(args(ciGateThreshold: 2));
      expect(
        r.exitCode,
        CliExitCode.clean,
        reason: 'the threshold is a ceiling, not a target — 2 of 2 is inside',
      );
    });

    test('over the ceiling exits 4', () async {
      final r = await runnerWith([
        _FakeEngine(
          'fake',
          violations: [
            violation(),
            violation(rule: 'b'),
            violation(rule: 'c'),
          ],
        ),
      ]).run(args(ciGateThreshold: 2));
      expect(r.exitCode, CliExitCode.overThreshold);
    });

    test('a zero ceiling gates on the first violation', () async {
      final r = await runnerWith([
        _FakeEngine('fake', violations: [violation()]),
      ]).run(args(ciGateThreshold: 0));
      expect(r.exitCode, CliExitCode.overThreshold);
    });

    test('a zero ceiling passes a genuinely clean run', () async {
      final r = await runnerWith([
        _FakeEngine('fake'),
      ]).run(args(ciGateThreshold: 0));
      expect(r.exitCode, CliExitCode.clean);
    });

    test('the org ceiling outranks the team gates', () async {
      // Both would fire. The ceiling wins because it is the outer
      // constraint: being over the organization's budget blocks whether or
      // not this change caused it, and a regression that stays under it is
      // the softer signal.
      final r = await runnerWith([
        _FakeEngine(
          'fake',
          violations: [
            violation(),
            violation(rule: 'b'),
            violation(rule: 'c'),
          ],
        ),
      ]).run(args(ciGateThreshold: 1, exitCode: true, failOnNew: true));
      expect(r.exitCode, CliExitCode.overThreshold);
    });

    test('a broken run still outranks the ceiling', () async {
      // The violation count from a run where an engine died is a partial
      // result. Reporting "over budget" for it would be a number nobody can
      // act on, and reporting "under budget" would be worse.
      final r = await runnerWith([
        _FakeEngine(
          'fake',
          error: const EngineRunFailedException(
            engineId: 'fake',
            exitCode: 1,
            reason: 'rejected a flag',
          ),
        ),
      ]).run(args(ciGateThreshold: 0));
      expect(r.exitCode, CliExitCode.runFailed);
    });
  });

  group('waivers and severity overrides still apply', () {
    test('a source pragma suppresses a violation and the gate', () async {
      File(sourcePath).writeAsStringSync('''
// verilator lint_off WIDTHTRUNC
module top; endmodule
// verilator lint_on WIDTHTRUNC
''');
      final r = await runnerWith([
        _FakeEngine(
          'verilator',
          violations: [
            Violation(
              engineId: 'verilator',
              ruleId: 'verilator/WIDTHTRUNC',
              severity: Severity.warning,
              message: 'truncation',
              location: SourceLocation(file: sourcePath, line: 2, column: 1),
            ),
          ],
        ),
      ]).run(args(exitCode: true));
      expect(r.suppressedCount, 1);
      expect(r.reportableViolations, isEmpty);
      expect(r.exitCode, CliExitCode.clean);
    });

    test('--config severity overrides reach the run', () async {
      final configPath = p.join(tmp.path, 'ci.lintcrux');
      File(configPath).writeAsStringSync(
        jsonEncode(<String, Object?>{
          'severityOverrides': <String, String>{'fake/RULE': 'note'},
        }),
      );
      final r = await runnerWith([
        _FakeEngine('fake', violations: [violation(severity: Severity.error)]),
      ]).run(args(config: configPath));
      expect(r.reportableViolations.single.severity, Severity.note);
    });

    test('a malformed --config fails the run, never silently', () async {
      final configPath = p.join(tmp.path, 'ci.lintcrux');
      File(configPath).writeAsStringSync('{"severityOverrides": 5}');
      final r = await runnerWith([_FakeEngine('fake')]).run(
        args(config: configPath),
      );
      expect(r.exitCode, CliExitCode.runFailed);
    });
  });

  group('--export', () {
    test('writes SARIF to --out and reports the path', () async {
      final out = p.join(tmp.path, 'nested', 'lint.sarif');
      final r = await runnerWith([
        _FakeEngine('fake', violations: [violation()]),
      ]).run(args(exportFormat: 'sarif', out: out));
      expect(r.exportPath, out);
      expect(File(out).existsSync(), isTrue);
      final decoded = jsonDecode(File(out).readAsStringSync());
      expect((decoded as Map)['version'], '2.1.0');
    });

    test('an unwritable --out fails the run (3)', () async {
      final r =
          await runnerWith([
            _FakeEngine('fake', violations: [violation()]),
          ]).run(
            args(
              exportFormat: 'sarif',
              out: p.join(sourcePath, 'cannot', 'be', 'a', 'dir.sarif'),
            ),
          );
      expect(r.exitCode, CliExitCode.runFailed);
    });
  });
}
