// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/services/engines/bundled_binary_resolver.dart';
import 'package:lintcrux/services/engines/yosys/yosys_engine_support.dart';

/// Records what it was asked to spawn and answers with a clean exit.
class _RecordingProcessRunner implements ProcessRunner {
  String? workingDirectory;
  Map<String, String>? environment;

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
    this.workingDirectory = workingDirectory;
    this.environment = environment;
    return const ProcessRunResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  group('yosysExecutableFor', () {
    test('Custom returns the configured path', () {
      expect(
        yosysExecutableFor(
          const EngineBinaryConfig(
            source: EngineBinarySource.custom,
            path: '/opt/y/bin/yosys',
          ),
        ),
        '/opt/y/bin/yosys',
      );
    });

    test('Custom with no path falls back to the PATH default', () {
      expect(
        yosysExecutableFor(
          const EngineBinaryConfig(
            source: EngineBinarySource.custom,
            path: '',
          ),
        ),
        isNull,
      );
    });

    test('Auto-detect is the PATH default', () {
      expect(yosysExecutableFor(const EngineBinaryConfig.system()), isNull);
    });

    test('Bundled with no bundled binary falls back to PATH', () {
      expect(
        yosysExecutableFor(
          const EngineBinaryConfig(source: EngineBinarySource.bundled),
          resolver: const BundledBinaryResolver(
            overrideRoot: '/nonexistent/lintcrux-bundle',
          ),
        ),
        isNull,
      );
    });
  });

  group('yosysRunException', () {
    test('a launch failure is an unavailable engine', () {
      const result = YosysRunFailure(
        kind: YosysFailureKind.launch,
        exitCode: YosysRunner.launchFailureExitCode,
        stdout: '',
        stderr: 'Could not run the executable "yosys": No such file',
      );
      expect(
        yosysRunException(engineId: 'yosys', result: result),
        isA<EngineNotAvailableException>(),
      );
    });

    test('a rejected request is a failed run, not a missing binary', () {
      const result = YosysRunFailure(
        kind: YosysFailureKind.invalidRequest,
        exitCode: YosysRunner.launchFailureExitCode,
        stdout: '',
        stderr: 'Invalid Yosys request: Path must not contain quotes',
      );
      expect(
        yosysRunException(engineId: 'yosys', result: result),
        isA<EngineRunFailedException>(),
      );
    });

    test('the kind decides a launch failure, not the stderr wording', () {
      // A launch failure whose message does not open with the runner's
      // usual prefix is still a missing binary...
      const launch = YosysRunFailure(
        kind: YosysFailureKind.launch,
        exitCode: YosysRunner.launchFailureExitCode,
        stdout: '',
        stderr: 'spawn failed',
      );
      expect(
        yosysRunException(engineId: 'yosys', result: launch),
        isA<EngineNotAvailableException>(),
      );

      // ...and a failure of another kind that happens to carry that prefix
      // is not.
      const unreadable = YosysRunFailure(
        kind: YosysFailureKind.outputUnreadable,
        exitCode: YosysRunner.launchFailureExitCode,
        stdout: '',
        stderr: 'Could not run the executable "yosys"',
      );
      expect(
        yosysRunException(engineId: 'yosys', result: unreadable),
        isA<EngineRunFailedException>(),
      );
    });

    test('a failure built without a kind keeps its exit-code meaning', () {
      // `YosysRunFailure.kind` derives -1 as a launch failure when none is
      // given, so a test double written before the field existed still
      // reads as a missing binary.
      const result = YosysRunFailure(
        exitCode: YosysRunner.launchFailureExitCode,
        stdout: '',
        stderr: 'Could not run the executable "yosys": No such file',
      );
      expect(
        yosysRunException(engineId: 'yosys', result: result),
        isA<EngineNotAvailableException>(),
      );
    });

    for (final (kind, exitCode, reason) in <(YosysFailureKind, int, String)>[
      (
        YosysFailureKind.invalidRequest,
        YosysRunner.launchFailureExitCode,
        'request could not be turned into a yosys script',
      ),
      (
        YosysFailureKind.outputUnreadable,
        YosysRunner.launchFailureExitCode,
        'JSON output could not be read back',
      ),
      (YosysFailureKind.noOutput, 0, 'without writing its JSON output'),
      (YosysFailureKind.nonZeroExit, 1, 'without a parseable diagnostic'),
    ]) {
      test('${kind.name} is a failed run that says which failure it was', () {
        final result = YosysRunFailure(
          kind: kind,
          exitCode: exitCode,
          stdout: '',
          stderr: 'detail',
        );
        expect(
          yosysRunException(
            engineId: 'yosys',
            result: result,
            executable: '/opt/y/bin/yosys',
          ),
          isA<EngineRunFailedException>()
              .having((e) => e.exitCode, 'exitCode', exitCode)
              .having((e) => e.reason, 'reason', contains(reason))
              .having((e) => e.outputExcerpt, 'outputExcerpt', ['detail'])
              .having(
                (e) => e.resolvedPath,
                'resolvedPath',
                '/opt/y/bin/yosys',
              ),
        );
      });
    }

    test('a timeout carries its budget', () {
      const result = YosysRunTimeout(
        budget: Duration(seconds: 5),
        stdout: '',
        stderr: '',
      );
      expect(
        yosysRunException(engineId: 'cdc', result: result),
        isA<EngineTimedOutException>().having(
          (e) => e.timeout,
          'timeout',
          const Duration(seconds: 5),
        ),
      );
    });

    test('a non-zero exit keeps the first stderr lines', () {
      const result = YosysRunFailure(exitCode: 1, stdout: '', stderr: 'a\n\nb');
      expect(
        yosysRunException(engineId: 'yosys', result: result),
        isA<EngineRunFailedException>().having(
          (e) => e.outputExcerpt,
          'outputExcerpt',
          ['a', 'b'],
        ),
      );
    });
  });

  group('yosysSourcesFor', () {
    test('reads each file under the language the project resolved', () {
      const request = LintRunRequest(
        sourceFiles: ['/p/top.sv', '/p/old.v', '/p/ent.vhd'],
        binary: EngineBinaryConfig.system(),
        language: HdlLanguage.mixed,
        sourceLanguages: {
          '/p/top.sv': HdlLanguage.systemVerilog,
          '/p/old.v': HdlLanguage.verilog,
          '/p/ent.vhd': HdlLanguage.vhdl,
        },
      );
      expect(yosysSourcesFor(request), const <YosysSourceFile>[
        YosysSourceFile.systemVerilog('/p/top.sv'),
        YosysSourceFile('/p/old.v'),
        YosysSourceFile.vhdl('/p/ent.vhd'),
      ]);
    });

    test('a request with no per-file languages uses the request one', () {
      const request = LintRunRequest(
        sourceFiles: ['/p/a.v', '/p/b.v'],
        binary: EngineBinaryConfig.system(),
        language: HdlLanguage.systemVerilog,
      );
      expect(
        yosysSourcesFor(request).map((s) => s.language),
        everyElement(YosysSourceLanguage.systemVerilog),
      );
    });

    test('a mixed request with no per-file languages falls back to the '
        'extension', () {
      const request = LintRunRequest(
        sourceFiles: ['/p/a.SV', '/p/b.svh', '/p/c.v', '/p/d.vhdl'],
        binary: EngineBinaryConfig.system(),
        language: HdlLanguage.mixed,
      );
      expect(yosysSourcesFor(request).map((s) => s.language), const [
        YosysSourceLanguage.systemVerilog,
        YosysSourceLanguage.systemVerilog,
        YosysSourceLanguage.verilog,
        YosysSourceLanguage.vhdl,
      ]);
    });
  });

  group('yosysDefinesFor', () {
    test('renders NAME and NAME=VALUE', () {
      const request = LintRunRequest(
        sourceFiles: ['/p/a.v'],
        binary: EngineBinaryConfig.system(),
        language: HdlLanguage.verilog,
        defines: {'SIM': '', 'WIDTH': '8'},
      );
      expect(yosysDefinesFor(request), ['SIM', 'WIDTH=8']);
    });
  });

  group('yosysWorkingDirectoryFor', () {
    LintRunRequest request({
      String root = '',
      List<String> sources = const ['/p/rtl/a.v'],
      Map<String, Object?> options = const {},
    }) => LintRunRequest(
      sourceFiles: sources,
      binary: const EngineBinaryConfig.system(),
      language: HdlLanguage.verilog,
      projectRoot: root,
      options: options,
    );

    test('the project root by default', () {
      expect(yosysWorkingDirectoryFor(request(root: '/p')), '/p');
    });

    test('the first source directory when there is no project root', () {
      expect(yosysWorkingDirectoryFor(request()), '/p/rtl');
    });

    test('null when there is nothing to anchor on', () {
      expect(yosysWorkingDirectoryFor(request(sources: const [])), isNull);
    });

    test('the workingDirectory option, relative to the root', () {
      expect(
        yosysWorkingDirectoryFor(
          request(root: '/p', options: const {'workingDirectory': 'sw'}),
        ),
        '/p/sw',
      );
    });

    test('an absolute workingDirectory option stands alone', () {
      expect(
        yosysWorkingDirectoryFor(
          request(
            root: '/p',
            options: const {'workingDirectory': '/images/'},
          ),
        ),
        '/images',
      );
    });

    test('an empty option is ignored', () {
      expect(
        yosysWorkingDirectoryFor(
          request(root: '/p', options: const {'workingDirectory': ''}),
        ),
        '/p',
      );
    });
  });

  group('EngineYosysProcessRunner', () {
    test(
      'spawns through the engine environment, from the run directory',
      () async {
        final inner = _RecordingProcessRunner();
        // The PATH launchd hands a GUI app: none of the package-manager
        // directories a terminal session would have.
        const launchdPath = '/usr/bin:/bin:/usr/sbin:/sbin';
        await EngineYosysProcessRunner(inner, workingDirectory: '/p').run(
          'yosys',
          const ['-V'],
          environment: const {'FOO': 'bar', 'PATH': launchdPath},
        );

        expect(inner.workingDirectory, '/p');
        final env = inner.environment!;
        expect(env['FOO'], 'bar');
        expect(env['NO_COLOR'], '1');
        expect(env['TERM'], 'dumb');
        final dirs = engineSearchDirs();
        if (dirs.isEmpty) {
          // Linux: nothing to append, the PATH is passed through.
          expect(env['PATH'], launchdPath);
        } else {
          final path = env['PATH']!.split(Platform.isWindows ? ';' : ':');
          expect(path, containsAll(dirs));
          expect(path.first, '/usr/bin', reason: 'appended, never prepended');
        }
      },
    );

    test('a caller-named working directory wins', () async {
      final inner = _RecordingProcessRunner();
      await EngineYosysProcessRunner(
        inner,
        workingDirectory: '/p',
      ).run('yosys', const [], workingDirectory: '/elsewhere');
      expect(inner.workingDirectory, '/elsewhere');
    });
  });

  group('isYosysDesignFailure', () {
    test('only a non-zero Yosys exit is a verdict on the design', () {
      for (final kind in YosysFailureKind.values) {
        final result = YosysRunFailure(
          kind: kind,
          exitCode: kind == YosysFailureKind.nonZeroExit ? 1 : -1,
          stdout: '',
          stderr: '',
        );
        expect(
          isYosysDesignFailure(result),
          kind == YosysFailureKind.nonZeroExit,
          reason: kind.name,
        );
      }
    });

    test('a success, a timeout and a cancellation are not', () {
      expect(
        isYosysDesignFailure(
          const YosysRunSuccess(rawJson: '{}', stdout: '', stderr: ''),
        ),
        isFalse,
      );
      expect(
        isYosysDesignFailure(
          const YosysRunTimeout(
            budget: Duration(seconds: 1),
            stdout: '',
            stderr: '',
          ),
        ),
        isFalse,
      );
      expect(
        isYosysDesignFailure(const YosysRunCancelled(stdout: '', stderr: '')),
        isFalse,
      );
    });
  });
}
