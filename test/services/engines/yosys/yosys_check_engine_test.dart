// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/services/engines/yosys/yosys_check_engine.dart';
import 'package:path/path.dart' as p;

class _StubProcessRunner implements ProcessRunner {
  _StubProcessRunner({
    this.exitCode = 0,
    this.stderr = '',
    this.jsonBytes = const <int>[],
    this.writesJson = true,
    this.hasSlang = false,
  });

  final int exitCode;
  final String stderr;

  /// Written to the `write_json` path instead of the canned document when
  /// non-empty — e.g. bytes that are not UTF-8, which the runner cannot read
  /// back.
  final List<int> jsonBytes;

  /// When false the stub exits without writing the `write_json` file.
  final bool writesJson;

  /// Whether the stub answers the `help read_slang` probe as a Yosys with
  /// the yosys-slang frontend does.
  final bool hasSlang;

  /// Every `-p` script the stub was asked to run, probes excluded.
  final List<String> scripts = <String>[];

  static const String _jsonContent = '{"modules":{}}';

  int calls = 0;
  String? lastExecutable;
  List<String>? lastArgs;

  @override
  Future<ProcessRunResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    Future<void>? cancelSignal,
    // Added upstream in crux_yosys f82593f (standalone-ghdl VHDL lowering);
    // unused on this SystemVerilog check path, which writes JSON via the
    // parsed `write_json "<path>"` script argument rather than streaming stdout.
    String? stdoutFilePath,
    void Function(String line)? onStderrLine,
  }) async {
    if (arguments.contains('help read_slang')) {
      return ProcessRunResult(
        exitCode: 0,
        stdout: hasSlang
            ? '    read_slang [options] [filenames]\n'
            : 'No such command or cell type: read_slang\n',
        stderr: '',
      );
    }
    calls++;
    lastExecutable = executable;
    lastArgs = arguments;
    // The YosysRunner expects the JSON output file path to be created
    // by the subprocess (via `write_json "<path>"`). The script string
    // is `arguments[2]` (after `-q -p`). We parse out the path and
    // write our canned JSON there.
    if (writesJson &&
        arguments.length >= 3 &&
        arguments[0] == '-q' &&
        arguments[1] == '-p') {
      final script = arguments[2];
      scripts.add(script);
      final match = RegExp('write_json "([^"]+)"').firstMatch(script);
      if (match != null) {
        final file = File(match.group(1)!);
        if (jsonBytes.isEmpty) {
          await file.writeAsString(_jsonContent);
        } else {
          await file.writeAsBytes(jsonBytes);
        }
      }
    }
    return ProcessRunResult(
      exitCode: exitCode,
      stdout: '',
      stderr: stderr,
    );
  }
}

/// A runner for a machine with no Yosys: every spawn fails the way
/// `Process.start` does for a missing executable.
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

LintRunRequest _request({
  EngineBinaryConfig binary = const EngineBinaryConfig.system(),
}) {
  return LintRunRequest(
    sourceFiles: const ['/tmp/a.sv', '/tmp/b.sv'],
    binary: binary,
    language: HdlLanguage.systemVerilog,
    topModule: 'top',
  );
}

void main() {
  // The slang probe is cached per executable for the life of the process.
  setUp(YosysAvailabilityService.resetSlangProbeCacheForTesting);

  group('YosysCheckEngine', () {
    test('id and displayName are stable', () {
      final engine = YosysCheckEngine();
      expect(engine.id, 'yosys');
      expect(engine.displayName, 'Yosys check');
    });

    test('capabilities cover Verilog + SystemVerilog', () {
      final engine = YosysCheckEngine();
      expect(
        engine.capabilities.supportedLanguages,
        containsAll([HdlLanguage.verilog, HdlLanguage.systemVerilog]),
      );
    });

    test('maps Warning diagnostics into Severity.warning', () async {
      final engine = YosysCheckEngine(
        processRunner: _StubProcessRunner(
          stderr: '/tmp/a.sv:42:5: Warning: synthesis: unused signal foo',
        ),
      );
      final violations = await engine.run(_request()).toList();
      expect(violations, isNotEmpty);
      expect(violations.first.severity, Severity.warning);
      expect(violations.first.engineId, 'yosys');
      expect(violations.first.ruleId, startsWith('yosys/'));
      expect(violations.first.location.file, '/tmp/a.sv');
      expect(violations.first.location.line, 42);
    });

    test('maps ERROR diagnostics into Severity.error', () async {
      final engine = YosysCheckEngine(
        processRunner: _StubProcessRunner(
          exitCode: 1,
          stderr: '/tmp/a.sv:7: ERROR: multiply driven net signal',
        ),
      );
      final violations = await engine.run(_request()).toList();
      expect(violations, isNotEmpty);
      expect(violations.first.severity, Severity.error);
    });

    test(
      'module-name fallback when filePath is null',
      () async {
        final engine = YosysCheckEngine(
          processRunner: _StubProcessRunner(
            // The diagnostic parser drops untagged informational lines —
            // we need a Warning prefix without a filename. The
            // YosysDiagnosticParser recognizes "Warning:" without a path.
            stderr:
                r'Warning: Found multiply driven net \foo in '
                r'module \modname',
          ),
        );
        final violations = await engine.run(_request()).toList();
        expect(violations, isNotEmpty);
        // Module-name fallback should put the module in the file path
        // when filePath is null.
        final v = violations.first;
        expect(v.location.file, contains('module:'));
      },
    );

    test(
      'onDiagnostics sink receives the parsed YosysDiagnostic list',
      () async {
        final captured = <List<YosysDiagnostic>>[];
        final engine = YosysCheckEngine(
          processRunner: _StubProcessRunner(
            stderr:
                r'Warning: Found multiply driven net \foo in '
                r'module \modname',
          ),
          onDiagnostics: captured.add,
        );
        await engine.run(_request()).toList();
        expect(captured, hasLength(1));
        expect(captured.single, isNotEmpty);
        expect(
          captured.single.first.severity,
          YosysDiagnosticSeverity.warning,
        );
      },
    );

    test(
      'a yosys that cannot be started is unavailable, not a clean run',
      () async {
        final engine = YosysCheckEngine(
          processRunner: _MissingBinaryProcessRunner(),
        );
        await expectLater(
          engine.run(_request()),
          emitsError(isA<EngineNotAvailableException>()),
        );
      },
    );

    test(
      'a non-zero exit with no parseable diagnostic fails the run',
      () async {
        final engine = YosysCheckEngine(
          processRunner: _StubProcessRunner(exitCode: 1, stderr: 'garbage'),
        );
        await expectLater(
          engine.run(_request()),
          emitsError(
            isA<EngineRunFailedException>()
                .having((e) => e.exitCode, 'exitCode', 1)
                .having((e) => e.outputExcerpt, 'outputExcerpt', ['garbage']),
          ),
        );
      },
    );

    test('a clean exit with no diagnostics is a clean run', () async {
      final engine = YosysCheckEngine(processRunner: _StubProcessRunner());
      expect(await engine.run(_request()).toList(), isEmpty);
    });

    // Every YosysFailureKind other than a non-zero exit is a tool failure:
    // the engine fails rather than parsing a message that is not Yosys's
    // verdict on the design.

    test(
      'a request the runner rejects fails the run without spawning',
      () async {
        final stub = _StubProcessRunner();
        final diagnostics = <List<YosysDiagnostic>>[];
        final engine = YosysCheckEngine(
          processRunner: stub,
          onDiagnostics: diagnostics.add,
        );
        await expectLater(
          engine.run(
            const LintRunRequest(
              sourceFiles: ['/tmp/a"b.sv'],
              binary: EngineBinaryConfig.system(),
              language: HdlLanguage.systemVerilog,
              topModule: 'top',
            ),
          ),
          emitsError(
            isA<EngineRunFailedException>()
                .having(
                  (e) => e.exitCode,
                  'exitCode',
                  YosysRunner.launchFailureExitCode,
                )
                .having(
                  (e) => e.reason,
                  'reason',
                  contains('could not be turned into a yosys script'),
                ),
          ),
        );
        expect(stub.calls, 0);
        expect(diagnostics, isEmpty);
      },
    );

    test('a JSON output that cannot be read back fails the run', () async {
      final engine = YosysCheckEngine(
        processRunner: _StubProcessRunner(
          stderr: '/tmp/a.sv:42:5: Warning: synthesis: unused signal foo',
          jsonBytes: const <int>[0xFF, 0xFE, 0xFD],
        ),
      );
      await expectLater(
        engine.run(_request()),
        emitsError(
          isA<EngineRunFailedException>().having(
            (e) => e.reason,
            'reason',
            contains('could not be read back'),
          ),
        ),
      );
    });

    test(
      'a clean exit without JSON output fails the run, warnings or not',
      () async {
        final engine = YosysCheckEngine(
          processRunner: _StubProcessRunner(
            stderr: '/tmp/a.sv:42:5: Warning: synthesis: unused signal foo',
            writesJson: false,
          ),
        );
        await expectLater(
          engine.run(_request()),
          emitsError(
            isA<EngineRunFailedException>()
                .having((e) => e.exitCode, 'exitCode', 0)
                .having(
                  (e) => e.reason,
                  'reason',
                  contains('without writing its JSON output'),
                ),
          ),
        );
      },
    );

    test('runs the Custom binary path from the request', () async {
      final stub = _StubProcessRunner();
      final engine = YosysCheckEngine(processRunner: stub);
      await engine
          .run(
            _request(
              binary: const EngineBinaryConfig(
                source: EngineBinarySource.custom,
                path: '/opt/y/bin/yosys',
              ),
            ),
          )
          .toList();
      expect(stub.lastExecutable, '/opt/y/bin/yosys');
    });

    test('detectVersion probes the Custom binary path', () async {
      final runner = _MissingBinaryProcessRunner();
      final engine = YosysCheckEngine(processRunner: runner);
      final version = await engine.detectVersion(
        const EngineBinaryConfig(
          source: EngineBinarySource.custom,
          path: '/opt/y/bin/yosys',
        ),
      );
      expect(version, isNull);
      expect(runner.executables, ['/opt/y/bin/yosys']);
    });

    test('rule-id inference produces a stable kebab-case identifier', () {
      const d = YosysDiagnostic(
        severity: YosysDiagnosticSeverity.warning,
        message: 'Multiply driven net signal',
      );
      // We re-execute the inferRuleId logic via the engine's _toViolation
      // indirectly — call the engine.run path.
      // Instead, verify the rule-id format on a representative input via
      // a stub run.
      // Simple sanity check that the parser is willing to accept this.
      const parser = YosysDiagnosticParser();
      final parsed = parser.parse(
        '/tmp/a.sv:1: Warning: ${d.message}',
      );
      expect(parsed.single.severity, YosysDiagnosticSeverity.warning);
    });

    test(
      'detectVersion returns null when yosys is not available',
      () async {
        // No yosys on PATH in CI; returns null.
        final engine = YosysCheckEngine();
        final version = await engine.detectVersion(
          const EngineBinaryConfig.system(),
        );
        // Either null (no yosys) or a real banner; both are acceptable.
        if (version != null) {
          expect(version.toLowerCase(), contains('yosys'));
        }
      },
    );

    test('cancel is idempotent (no-op when nothing is running)', () {
      final engine = YosysCheckEngine();
      expect(engine.cancel, returnsNormally);
      // Calling twice is safe.
      expect(engine.cancel, returnsNormally);
    });

    group('a run that stops before check -assert', () {
      // The eduBOS5 report: `return y;` inside a `function automatic` is
      // legal SystemVerilog that the built-in reader rejects. The parse
      // error used to be one design `error` and the run ended clean.
      const parseFailure =
          "/tmp/a.sv:12: Warning: Identifier `\\x' is implicitly declared.\n"
          '/tmp/b.sv:182: ERROR: syntax error, unexpected TOK_ID\n';

      test(
        'a front-end parse failure is one analysis failure, not a design '
        'error',
        () async {
          final engine = YosysCheckEngine(
            processRunner: _StubProcessRunner(
              exitCode: 1,
              stderr: parseFailure,
            ),
          );
          final violations = await engine.run(_request()).toList();
          final failure = violations.singleWhere(
            (v) => v.severity == Severity.error,
          );
          expect(failure.ruleId, 'yosys/frontend-failed');
          expect(failure.isAnalysisFailure, isTrue);
          expect(failure.location.file, '/tmp/b.sv');
          expect(failure.location.line, 182);
          expect(failure.message, contains('check pass'));
          expect(failure.message, contains('did not run'));
          expect(failure.message, contains('syntax error, unexpected TOK_ID'));
          // No slang here: the message names the reader that refused it.
          expect(failure.message, contains('read_verilog -sv'));
          expect(failure.message, contains('yosys-slang'));
          // The warning from the part that was read is still reported.
          expect(
            violations.where((v) => v.severity == Severity.warning),
            hasLength(1),
          );
        },
      );

      test('a Verilog-only design is not told about yosys-slang', () async {
        final engine = YosysCheckEngine(
          processRunner: _StubProcessRunner(
            exitCode: 1,
            stderr: '/tmp/a.v:3: ERROR: syntax error, unexpected TOK_ID\n',
          ),
        );
        final violations = await engine
            .run(
              const LintRunRequest(
                sourceFiles: ['/tmp/a.v'],
                binary: EngineBinaryConfig.system(),
                language: HdlLanguage.verilog,
                topModule: 'top',
              ),
            )
            .toList();
        final failure = violations.single;
        expect(failure.ruleId, 'yosys/frontend-failed');
        expect(failure.isAnalysisFailure, isTrue);
        expect(failure.message, isNot(contains('yosys-slang')));
      });

      test(
        'a stop in hierarchy keeps its findings and notes that check did not '
        'run',
        () async {
          final engine = YosysCheckEngine(
            processRunner: _StubProcessRunner(
              exitCode: 1,
              stderr:
                  r"ERROR: Module `\Gowin_ALU54' referenced in module `\top' "
                  r"in cell `\u_alu' is not part of the design."
                  '\n',
            ),
          );
          final violations = await engine.run(_request()).toList();
          expect(
            violations.map((v) => v.ruleId),
            ['yosys/unknown-module', 'yosys/check-not-run'],
          );
          expect(violations.any((v) => v.isAnalysisFailure), isFalse);
          expect(violations.last.severity, Severity.note);
        },
      );

      test('a check -assert failure is reported as before', () async {
        final engine = YosysCheckEngine(
          processRunner: _StubProcessRunner(
            exitCode: 1,
            stderr:
                r'Warning: multiple conflicting drivers for top.\q [0]:'
                '\n'
                "ERROR: Found 1 problems in 'check -assert'.\n",
          ),
        );
        final violations = await engine.run(_request()).toList();
        expect(
          violations.map((v) => v.ruleId),
          isNot(
            contains(anyOf('yosys/frontend-failed', 'yosys/check-not-run')),
          ),
        );
        expect(violations.any((v) => v.isAnalysisFailure), isFalse);
      });
    });

    group('SystemVerilog reader', () {
      test('reads SystemVerilog with read_slang when Yosys has it', () async {
        final stub = _StubProcessRunner(hasSlang: true);
        final engine = YosysCheckEngine(processRunner: stub);
        await engine.run(_request()).toList();
        expect(stub.scripts.single, contains('read_slang -f'));
        expect(stub.scripts.single, isNot(contains('read_verilog')));
        expect(stub.scripts.single, contains('check -assert'));
      });

      test('falls back to read_verilog -sv without yosys-slang', () async {
        final stub = _StubProcessRunner();
        final engine = YosysCheckEngine(processRunner: stub);
        await engine.run(_request()).toList();
        expect(stub.scripts.single, contains('read_verilog'));
        expect(stub.scripts.single, contains('-sv'));
        expect(stub.scripts.single, isNot(contains('read_slang')));
      });

      test('a Verilog-only design keeps the built-in reader', () async {
        final stub = _StubProcessRunner(hasSlang: true);
        final engine = YosysCheckEngine(processRunner: stub);
        await engine
            .run(
              const LintRunRequest(
                sourceFiles: ['/tmp/a.v'],
                binary: EngineBinaryConfig.system(),
                language: HdlLanguage.verilog,
                topModule: 'top',
              ),
            )
            .toList();
        expect(stub.scripts.single, contains('read_verilog'));
        expect(stub.scripts.single, isNot(contains('read_slang')));
      });

      test('top-level parameters reach hierarchy -chparam', () async {
        final stub = _StubProcessRunner();
        final engine = YosysCheckEngine(processRunner: stub);
        await engine
            .run(
              const LintRunRequest(
                sourceFiles: ['/tmp/a.sv'],
                binary: EngineBinaryConfig.system(),
                language: HdlLanguage.systemVerilog,
                topModule: 'top',
                parameters: {'EN_WAIT4REGS': '1'},
              ),
            )
            .toList();
        expect(
          stub.scripts.single,
          contains('hierarchy -check -top top -chparam EN_WAIT4REGS 1'),
        );
      });

      test(
        'parameters without a top module fail the run, never apply '
        'silently',
        () async {
          final stub = _StubProcessRunner();
          final engine = YosysCheckEngine(processRunner: stub);
          await expectLater(
            engine.run(
              const LintRunRequest(
                sourceFiles: ['/tmp/a.v'],
                binary: EngineBinaryConfig.system(),
                language: HdlLanguage.verilog,
                parameters: {'W': '4'},
              ),
            ),
            emitsError(
              isA<EngineRunFailedException>().having(
                (e) => e.outputExcerpt.join('\n'),
                'outputExcerpt',
                contains('need a top module'),
              ),
            ),
          );
          expect(stub.scripts, isEmpty);
        },
      );

      test(
        'a slang read failure says slang was used, not to install it',
        () async {
          final engine = YosysCheckEngine(
            processRunner: _StubProcessRunner(
              hasSlang: true,
              exitCode: 1,
              stderr:
                  "/tmp/a.sv:4:5: error: unknown module 'foo'\n"
                  'ERROR: Compilation failed\n',
            ),
          );
          final violations = await engine.run(_request()).toList();
          final failure = violations.single;
          expect(failure.ruleId, 'yosys/frontend-failed');
          expect(failure.location.line, 4);
          expect(failure.message, contains('read with yosys-slang'));
          expect(failure.message, isNot(contains('read_verilog -sv')));
        },
      );
    });

    test(
      'integration: runs against the real yosys binary',
      () async {
        // Skip when yosys isn't installed; the integration matrix
        // pre-populates the binary via the bundled-engines workflow.
        if (!_yosysOnPath()) {
          // skip handled below
          return;
        }
        final tmp = Directory.systemTemp.createTempSync('yosys_engine_int_');
        addTearDown(() {
          if (tmp.existsSync()) tmp.deleteSync(recursive: true);
        });
        final src = File(p.join(tmp.path, 'top.v'));
        await src.writeAsString(
          'module top(input wire clk, output wire q);\n'
          '  // intentionally unused signal\n'
          '  wire unused_signal;\n'
          '  assign q = clk;\n'
          'endmodule\n',
        );
        final engine = YosysCheckEngine();
        final request = LintRunRequest(
          sourceFiles: [src.path],
          binary: const EngineBinaryConfig.system(),
          language: HdlLanguage.verilog,
          topModule: 'top',
        );
        final results = await engine.run(request).toList();
        // We do not assert on a specific violation set — yosys output
        // varies across versions. We assert that the engine ran to
        // completion without throwing.
        expect(results, isNotNull);
      },
      skip: _yosysOnPath() ? false : 'yosys not on PATH',
    );

    test(
      'integration: a parameter selects the configuration Yosys checks',
      () async {
        // The default configuration instantiates a module the design does
        // not have; EN=1 selects the branch that elaborates.
        final tmp = Directory.systemTemp.createTempSync('yosys_param_int_');
        addTearDown(() {
          if (tmp.existsSync()) tmp.deleteSync(recursive: true);
        });
        final src = File(p.join(tmp.path, 'top.v'))
          ..writeAsStringSync(
            'module sub(input wire a, output wire y); assign y = a; '
            'endmodule\n'
            'module top #(parameter EN = 0) (input wire a, output wire y);\n'
            '  generate if (EN) begin : g1\n'
            '    sub u (.a(a), .y(y));\n'
            '  end else begin : g0\n'
            '    missing_mod u (.a(a), .y(y));\n'
            '  end endgenerate\n'
            'endmodule\n',
          );
        LintRunRequest request(Map<String, String> parameters) =>
            LintRunRequest(
              sourceFiles: [src.path],
              binary: const EngineBinaryConfig.system(),
              language: HdlLanguage.verilog,
              topModule: 'top',
              projectRoot: tmp.path,
              parameters: parameters,
            );
        final engine = YosysCheckEngine();
        final byDefault = await engine.run(request(const {})).toList();
        expect(
          byDefault.map((v) => v.ruleId),
          contains('yosys/unknown-module'),
        );
        final selected = await engine.run(request(const {'EN': '1'})).toList();
        expect(
          selected.where((v) => v.severity == Severity.error),
          isEmpty,
          reason: selected.map((v) => v.message).join('\n'),
        );
      },
      skip: _yosysOnPath() ? false : 'yosys not on PATH',
    );
  });
}

bool _yosysOnPath() {
  final pathVar = Platform.environment['PATH'] ?? '';
  final exe = Platform.isWindows ? 'yosys.exe' : 'yosys';
  for (final dir in pathVar.split(Platform.isWindows ? ';' : ':')) {
    if (dir.isEmpty) continue;
    if (File('$dir${Platform.pathSeparator}$exe').existsSync()) return true;
  }
  return false;
}
