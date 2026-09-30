// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/ghdl/ghdl_engine.dart';
import 'package:lintcrux/services/engines/process_runner.dart';
import 'package:lintcrux/services/engines/slang/slang_engine.dart';
import 'package:lintcrux/services/engines/svlint/svlint_engine.dart';
import 'package:lintcrux/services/engines/verible/verible_engine.dart';
import 'package:lintcrux/services/engines/verilator/verilator_engine.dart';

/// An engine's output is read to end-of-file, never merely to its exit.
///
/// A real process reports its exit code and its output on separate channels,
/// and nothing orders them: the exit routinely arrives while the last lines
/// are still in the pipe. The adapters used to stop reading the moment the
/// exit code arrived, which on CI dropped Verible's one-line rejection of
/// `--lint_output` (so the text-mode retry never ran) two runs in three. For
/// the engines that ignore their exit code — Slang, GHDL, svlint — and for
/// Verilator, whose failure guard needs an `%Error` line it never saw, the
/// same drop reported a clean run.
///
/// These fakes make that ordering deterministic: the exit code completes, the
/// exit's awaiters run, and only THEN does the output arrive. Every adapter
/// must still see all of it.
void main() {
  group('every engine adapter reads its output past the exit code', () {
    test('Verible sees a rejection that lands after the exit, and retries '
        'in text mode', () async {
      final runner = _LateOutputRunner([
        const _Script(
          stderrAfterExit: ["ERROR: Unknown command line flag 'lint_output'"],
          exitCode: 1,
        ),
        const _Script(
          stderrAfterExit: ['top.sv:1:1-4: Use spaces, not tabs. [no-tabs]'],
          exitCode: 1,
        ),
      ]);

      final violations = await _run(
        VeribleEngine(runner: runner, projectRoot: '/work'),
        '/work/top.sv',
        HdlLanguage.systemVerilog,
      );

      expect(
        runner.invocations,
        2,
        reason: 'the rejection was read, so the text-mode retry ran',
      );
      expect(violations.map((v) => v.ruleId), ['verible/no-tabs']);
    });

    test(
      'Slang reports the findings whose JSON lands after the exit',
      () async {
        final violations = await _run(
          SlangEngine(
            runner: _LateOutputRunner([
              const _Script(stdoutAfterExit: [_slangJson]),
            ]),
            projectRoot: '/work',
          ),
          '/work/top.sv',
          HdlLanguage.systemVerilog,
        );

        expect(violations, hasLength(1));
      },
    );

    test('Slang: one late line (the closing bracket) no longer empties the '
        'whole run', () async {
      final violations = await _run(
        SlangEngine(
          runner: _LateOutputRunner([
            const _Script(
              stdoutBeforeExit: ['[', '  $_slangJson'],
              stdoutAfterExit: [']'],
            ),
          ]),
          projectRoot: '/work',
        ),
        '/work/top.sv',
        HdlLanguage.systemVerilog,
      );

      expect(violations, hasLength(1));
    });

    test('Verilator reports the warnings that land after the exit', () async {
      final violations = await _run(
        VerilatorEngine(
          runner: _LateOutputRunner([
            const _Script(
              stderrAfterExit: [
                '%Warning-UNUSEDSIGNAL: top.sv:42:13: unused',
                '   42 | logic x;',
              ],
              exitCode: 1,
            ),
          ]),
          projectRoot: '/work',
        ),
        '/work/top.sv',
        HdlLanguage.systemVerilog,
      );

      expect(violations, hasLength(1));
    });

    test('GHDL reports the diagnostics that land after the exit', () async {
      final violations = await _run(
        GhdlEngine(
          runner: _LateOutputRunner([
            const _Script(
              stderrAfterExit: [
                'design.vhd:42:13: warning: unused variable "x" [-Wunused]',
              ],
            ),
          ]),
          projectRoot: '/work',
        ),
        '/work/design.vhd',
        HdlLanguage.vhdl,
      );

      expect(violations, hasLength(1));
    });

    test('svlint reports the findings that land after the exit', () async {
      final violations = await _run(
        SvlintEngine(
          runner: _LateOutputRunner([
            const _Script(stdoutAfterExit: [_svlintJson], exitCode: 1),
          ]),
          projectRoot: '/work',
        ),
        '/work/top.sv',
        HdlLanguage.systemVerilog,
      );

      expect(violations, hasLength(1));
    });

    test('detectVersion reads a banner that lands after the exit', () async {
      final version = await VerilatorEngine(
        runner: _LateOutputRunner([
          const _Script(stdoutAfterExit: ['Verilator 5.022 2024-07-01']),
        ]),
      ).detectVersion(const EngineBinaryConfig.system());

      expect(version, 'Verilator 5.022 2024-07-01');
    });
  });

  group('collectProcessOutput', () {
    test(
      'keeps every line, in order, from before and after the exit',
      () async {
        final process = _LateOutputProcess(
          const _Script(
            stdoutBeforeExit: ['a', 'b'],
            stdoutAfterExit: ['c'],
            stderrBeforeExit: ['x'],
            stderrAfterExit: ['y', 'z'],
            exitCode: 3,
          ),
        );

        final output = await collectProcessOutput(
          process,
          engineId: 'probe',
          executable: 'probe',
        );

        expect(output.exitCode, 3);
        expect(output.stdout, ['a', 'b', 'c']);
        expect(output.stderr, ['x', 'y', 'z']);
      },
    );

    test('a stream still open after the grace fails the run instead of '
        'returning what arrived so far', () async {
      final process = _LateOutputProcess(
        const _Script(stdoutBeforeExit: ['partial']),
        neverClose: true,
      );

      await expectLater(
        collectProcessOutput(
          process,
          engineId: 'probe',
          executable: '/opt/probe',
          drainGrace: const Duration(milliseconds: 50),
        ),
        throwsA(
          isA<EngineRunFailedException>()
              .having((e) => e.engineId, 'engineId', 'probe')
              .having((e) => e.reason, 'reason', contains('still open'))
              .having((e) => e.outputExcerpt, 'outputExcerpt', ['partial']),
        ),
      );
    });

    test('a failed read fails the run instead of returning what arrived so '
        'far', () async {
      final process = _LateOutputProcess(
        const _Script(stdoutBeforeExit: ['partial']),
        stdoutError: const FileSystemException('pipe broke'),
      );

      await expectLater(
        collectProcessOutput(process, engineId: 'probe', executable: 'probe'),
        throwsA(
          isA<EngineRunFailedException>().having(
            (e) => e.reason,
            'reason',
            contains('reading its output failed'),
          ),
        ),
      );
    });
  });
}

const _slangJson =
    '{"severity":"warning", "code":"slang::diag::ImplicitConvert", '
    '"message":"Implicit conversion", '
    '"location":{"file":"top.sv","line":42,"column":13}}';

const _svlintJson =
    '{"path":"top.sv","line":4,"column":2, '
    '"rule":"non_blocking_assignment_in_always_comb","message":"m"}';

Future<List<Violation>> _run(
  LintEngine engine,
  String source,
  HdlLanguage language,
) {
  return engine
      .run(
        LintRunRequest(
          sourceFiles: [source],
          binary: const EngineBinaryConfig.system(),
          language: language,
        ),
      )
      .toList();
}

/// One scripted invocation: what arrives before the exit code, and what
/// arrives after it.
class _Script {
  const _Script({
    this.stdoutBeforeExit = const <String>[],
    this.stdoutAfterExit = const <String>[],
    this.stderrBeforeExit = const <String>[],
    this.stderrAfterExit = const <String>[],
    this.exitCode = 0,
  });

  final List<String> stdoutBeforeExit;
  final List<String> stdoutAfterExit;
  final List<String> stderrBeforeExit;
  final List<String> stderrAfterExit;
  final int exitCode;
}

class _LateOutputRunner implements ProcessRunner {
  _LateOutputRunner(this._scripts);

  final List<_Script> _scripts;
  int invocations = 0;

  @override
  Future<LintProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final script = _scripts[invocations.clamp(0, _scripts.length - 1)];
    invocations++;
    return _LateOutputProcess(script);
  }
}

/// A process whose exit code is known before its output is.
///
/// Once both streams have a listener it emits the "before" lines, completes
/// the exit code, and then waits a full event-loop turn — long enough for
/// everything awaiting the exit to run, including any code that would stop
/// listening there — before emitting the "after" lines and closing.
class _LateOutputProcess implements LintProcess {
  _LateOutputProcess(
    this._script, {
    this.neverClose = false,
    this.stdoutError,
  }) {
    _stdout.onListen = _onListen;
    _stderr.onListen = _onListen;
  }

  final _Script _script;

  /// Leaves stdout open after the exit, as a child holding the pipe would.
  final bool neverClose;

  /// Delivered on stdout after the exit, in place of a clean close.
  final Object? stdoutError;

  final _stdout = StreamController<String>.broadcast();
  final _stderr = StreamController<String>.broadcast();
  final _exit = Completer<int>();
  var _listeners = 0;

  void _onListen() {
    if (++_listeners == 2) unawaited(_play());
  }

  Future<void> _play() async {
    await Future<void>.microtask(() {});
    _script.stdoutBeforeExit.forEach(_stdout.add);
    _script.stderrBeforeExit.forEach(_stderr.add);
    _exit.complete(_script.exitCode);
    await Future<void>.delayed(Duration.zero);
    _script.stdoutAfterExit.forEach(_stdout.add);
    _script.stderrAfterExit.forEach(_stderr.add);
    await _stderr.close();
    if (stdoutError != null) {
      _stdout.addError(stdoutError!);
      return;
    }
    if (neverClose) return;
    await _stdout.close();
  }

  @override
  Stream<String> get stdout => _stdout.stream;

  @override
  Stream<String> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => -1;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}
