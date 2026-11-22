// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/cli/cli_args.dart';
import 'package:lintcrux/core/cli/cli_exit_codes.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/process_runner.dart';
import 'package:lintcrux/services/engines/slang/slang_engine.dart';
import 'package:lintcrux/services/headless/headless_run_result.dart';
import 'package:lintcrux/services/headless/headless_runner.dart';
import 'package:path/path.dart' as p;

import '../engines/fake_process_runner.dart';

/// A stand-in for slang that reports the way slang does: each file named in a
/// diagnostic is written relative to the directory slang ran in, unless the
/// command line says `--diag-abs-paths`.
///
/// Which diagnostics a file carries is scripted by file name. Nothing else
/// about slang is modelled, so a test fails only on the path handling.
class _SlangLikeRunner implements ProcessRunner {
  _SlangLikeRunner(this.findings, {this.honorsAbsPaths = true});

  /// File name to the line slang reports an error on.
  final Map<String, int> findings;

  /// Whether the pretend slang knows `--diag-abs-paths`.
  final bool honorsAbsPaths;

  final List<FakeInvocation> invocations = <FakeInvocation>[];

  /// The one invocation that linted, as opposed to a `--version` probe.
  FakeInvocation get lintRun =>
      invocations.singleWhere((i) => !i.arguments.contains('--version'));

  @override
  Future<LintProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    invocations.add(
      FakeInvocation(
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
      ),
    );
    final cwd = workingDirectory ?? Directory.current.path;
    final absolute = honorsAbsPaths && arguments.contains('--diag-abs-paths');
    final diagnostics = <Map<String, Object?>>[
      for (final a in arguments)
        if (a.endsWith('.sv') && findings.containsKey(p.basename(a)))
          <String, Object?>{
            'severity': 'error',
            'message': 'variable is driven by multiple always blocks',
            'optionName': 'multiple-always-assigns',
            'location':
                '${absolute ? a : p.relative(a, from: cwd)}'
                ':${findings[p.basename(a)]}:3',
          },
    ];
    return FakeLintProcess(
      stdoutLines: const JsonEncoder.withIndent(
        ' ',
      ).convert(diagnostics).split('\n'),
    );
  }
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lintcrux_layout_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  String write(String relative, [String content = 'module m; endmodule\n']) {
    final file = File(p.join(tmp.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file.path;
  }

  String project(List<String> sources) {
    final file = File(p.join(tmp.path, 'repro.lintcrux'))
      ..writeAsStringSync(
        jsonEncode(<String, Object?>{
          'version': 1,
          'name': 'repro',
          'rootPath': '.',
          'sourceFiles': sources,
          'enabledEngineIds': <String>['slang'],
        }),
      );
    return file.path;
  }

  Future<HeadlessRunResult> runSlang(
    _SlangLikeRunner runner,
    String projectPath,
  ) => HeadlessRunner(
    registry: EngineRegistry([SlangEngine(runner: runner)]),
  ).run(CliArgs(paths: <String>[projectPath], exitCodeOnFindings: true));

  group('sources in more than one folder', () {
    setUp(() {
      // The first source is a file nobody wrote by hand, in a folder of its
      // own; the design's defect is in a sibling folder.
      write('a/x.sv');
      write('b/t.sv');
    });

    test('a slang finding in the second folder survives the run', () async {
      final runner = _SlangLikeRunner(<String, int>{'t.sv': 4});
      final result = await runSlang(
        runner,
        project(<String>['a/x.sv', 'b/t.sv']),
      );
      expect(result.exitCode, CliExitCode.violations);
      expect(result.violations, hasLength(1));
      expect(
        result.violations.single.location.file,
        p.join(tmp.path, 'b/t.sv'),
      );
      expect(result.violations.single.location.line, 4);
      expect(runner.lintRun.workingDirectory, tmp.path);
    });

    test('the order of the files does not change the answer', () async {
      final runner = _SlangLikeRunner(<String, int>{'t.sv': 4});
      final result = await runSlang(
        runner,
        project(<String>['b/t.sv', 'a/x.sv']),
      );
      expect(result.exitCode, CliExitCode.violations);
      expect(result.violations, hasLength(1));
    });

    test('a slang that prints paths relative to the project root still '
        'reports it', () async {
      // slang before `--diag-abs-paths`, or a build that ignores it.
      final runner = _SlangLikeRunner(<String, int>{
        't.sv': 4,
      }, honorsAbsPaths: false);
      final result = await runSlang(
        runner,
        project(<String>['a/x.sv', 'b/t.sv']),
      );
      expect(result.exitCode, CliExitCode.violations);
      expect(result.violations, hasLength(1));
    });

    test('an ad-hoc run over files in two folders reports it', () async {
      final runner = _SlangLikeRunner(<String, int>{'t.sv': 4});
      final result =
          await HeadlessRunner(
            registry: EngineRegistry([SlangEngine(runner: runner)]),
          ).run(
            CliArgs(
              paths: <String>[
                p.join(tmp.path, 'a/x.sv'),
                p.join(tmp.path, 'b/t.sv'),
              ],
              engineIds: const <String>['slang'],
              exitCodeOnFindings: true,
            ),
          );
      expect(result.exitCode, CliExitCode.violations);
      expect(result.violations, hasLength(1));
    });
  });

  test(
    'a finding in a source outside the project root is reported',
    () async {
      final outside = Directory.systemTemp.createTempSync('lintcrux_outside_');
      addTearDown(() => outside.deleteSync(recursive: true));
      final shared = File(p.join(outside.path, 's.sv'))
        ..writeAsStringSync('module s; endmodule\n');
      write('a/x.sv');
      final runner = _SlangLikeRunner(<String, int>{'s.sv': 9});
      final result = await runSlang(
        runner,
        project(<String>['a/x.sv', shared.path]),
      );
      expect(result.exitCode, CliExitCode.violations);
      expect(result.violations.single.location.file, shared.path);
      expect(runner.lintRun.arguments, contains('--diag-abs-paths'));
    },
  );

  test(
    'a finding that cannot be placed is a failed run, never a clean one',
    () async {
      // The source lives outside the project root and this slang prints it
      // relative to where it ran (`../shared/s.sv`), which LintCrux refuses.
      final outside = Directory.systemTemp.createTempSync('lintcrux_outside_');
      addTearDown(() => outside.deleteSync(recursive: true));
      final shared = File(p.join(outside.path, 's.sv'))
        ..writeAsStringSync('module s; endmodule\n');
      write('a/x.sv');
      final runner = _SlangLikeRunner(<String, int>{
        's.sv': 9,
      }, honorsAbsPaths: false);
      final result = await runSlang(
        runner,
        project(<String>['a/x.sv', shared.path]),
      );
      expect(result.exitCode, CliExitCode.runFailed);
      expect(result.problems.join('\n'), contains('slang'));
    },
  );

  group('with a real slang', () {
    const tSv =
        'module t(input logic clk, a, output logic y);\n'
        '  logic m;\n'
        '  always_ff @(posedge clk) m <= a;\n'
        '  always_comb m = a;\n'
        '  assign y = m;\n'
        'endmodule\n';

    Future<HeadlessRunResult> run(List<String> sources) =>
        HeadlessRunner(registry: EngineRegistry([SlangEngine()])).run(
          CliArgs(
            paths: <String>[project(sources)],
            exitCodeOnFindings: true,
          ),
        );

    test(
      'an error in the second of two folders is reported',
      () async {
        write(
          'a/x.sv',
          'module x(input logic i, output logic o); assign o = i; endmodule\n',
        );
        write('b/t.sv', tSv);
        final result = await run(<String>['a/x.sv', 'b/t.sv']);
        expect(result.exitCode, CliExitCode.violations);
        expect(
          result.violations.map((v) => v.ruleId),
          contains('slang/multiple-always-assigns'),
        );
        expect(
          result.violations.first.location.file,
          p.join(tmp.path, 'b', 't.sv'),
        );
      },
      skip: _onPath('slang') ? false : 'slang not on PATH',
    );

    test(
      'an error in a source outside the project root is reported',
      () async {
        final outside = Directory.systemTemp.createTempSync('lintcrux_out_');
        addTearDown(() => outside.deleteSync(recursive: true));
        final shared = File(p.join(outside.path, 't.sv'))
          ..writeAsStringSync(tSv);
        write('a/x.sv');
        final result = await run(<String>['a/x.sv', shared.path]);
        expect(result.exitCode, CliExitCode.violations);
        // slang names the real path, which differs from the temp path where
        // that is a symlink (macOS).
        final reported = result.violations.first.location.file;
        expect(p.basename(reported), 't.sv');
        expect(p.basename(p.dirname(reported)), p.basename(outside.path));
      },
      skip: _onPath('slang') ? false : 'slang not on PATH',
    );
  });
}

bool _onPath(String binary) {
  final exe = Platform.isWindows ? '$binary.exe' : binary;
  final dirs = (Platform.environment['PATH'] ?? '').split(
    Platform.isWindows ? ';' : ':',
  );
  return dirs.any(
    (dir) => dir.isNotEmpty && File(p.join(dir, exe)).existsSync(),
  );
}
