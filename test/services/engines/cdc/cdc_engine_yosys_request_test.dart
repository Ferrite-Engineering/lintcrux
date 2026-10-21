// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/services/engines/cdc/cdc_engine.dart';

import '../../../support/posix_keyed_paths.dart';

// What the CDC engine asks Yosys to do, and how it is spawned.
//
// The engine used to hand every source to Yosys as Verilog-2005 with no
// include paths or defines, so a SystemVerilog design that elaborated under
// the Yosys check engine stopped at its first SystemVerilog-only token under
// CDC. It also spawned Yosys with the launching process's bare environment,
// so a Homebrew Yosys was "not available" from the Dock, and from whatever
// directory the user happened to be in, so a `$readmemh` image resolved or
// not depending on the shell.

/// Records the Yosys invocation and answers with a design failure, so the
/// run ends in `cdc/elaboration-failed` rather than in analysis.
class _RecordingProcessRunner implements ProcessRunner {
  String? script;
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
    if (arguments.length >= 3 && arguments[0] == '-q' && arguments[1] == '-p') {
      script = arguments[2];
    }
    return const ProcessRunResult(
      exitCode: 1,
      stdout: '',
      stderr: 'ERROR: syntax error, unexpected TOK_ID',
    );
  }
}

LintRunRequest _request({
  Map<String, Object?> options = const <String, Object?>{},
}) => LintRunRequest(
  sourceFiles: const ['/p/rtl/top.sv', '/p/rtl/old.v'],
  sourceLanguages: const {
    '/p/rtl/top.sv': HdlLanguage.systemVerilog,
    '/p/rtl/old.v': HdlLanguage.verilog,
  },
  includePaths: const ['/p/inc'],
  defines: const {'WIDTH': '8', 'SIM': ''},
  binary: const EngineBinaryConfig.system(),
  language: HdlLanguage.mixed,
  topModule: 'top',
  projectRoot: '/p',
  options: options,
);

void main() {
  group('CdcEngine hands Yosys the whole request', () {
    late _RecordingProcessRunner runner;
    late Directory temp;

    setUp(() {
      runner = _RecordingProcessRunner();
      temp = Directory.systemTemp.createTempSync('cdc-request-');
    });

    tearDown(() => temp.deleteSync(recursive: true));

    Future<List<String>> readCommands() async {
      await CdcEngine(
        processRunner: runner,
        tempDirectory: temp,
      ).run(_request()).toList();
      final script = runner.script;
      expect(script, isNotNull, reason: 'Yosys was not invoked');
      return script!
          .split(';')
          .map((c) => c.trim())
          .where((c) => c.startsWith('read_verilog'))
          .toList();
    }

    test(
      'a SystemVerilog file is read with -sv, a Verilog one without',
      () async {
        final reads = await readCommands();
        final sv = reads.singleWhere((c) => c.startsWith('read_verilog -sv'));
        final plain = reads.singleWhere(
          (c) => !c.startsWith('read_verilog -sv'),
        );
        expect(sv, contains('"/p/rtl/top.sv"'));
        expect(sv, isNot(contains('old.v')));
        expect(plain, contains('"/p/rtl/old.v"'));
        expect(plain, isNot(contains('top.sv')));
      },
    );

    test('include paths and defines reach every read command', () async {
      for (final read in await readCommands()) {
        expect(read, contains('-I /p/inc'));
        expect(read, contains('-D WIDTH=8'));
        expect(read, contains('-D SIM'));
      }
    });

    test('Yosys runs from the project root', () async {
      await CdcEngine(
        processRunner: runner,
        tempDirectory: temp,
      ).run(_request()).toList();
      expect(runner.workingDirectory, '/p');
    });

    test(
      'the workingDirectory option moves the run, relative to the root',
      () async {
        await CdcEngine(
          processRunner: runner,
          tempDirectory: temp,
        ).run(_request(options: const {'workingDirectory': 'sw'})).toList();
        expect(posixKey(runner.workingDirectory!), '/p/sw');
      },
    );

    test('Yosys is spawned with the engine environment', () async {
      await CdcEngine(
        processRunner: runner,
        tempDirectory: temp,
      ).run(_request()).toList();
      final env = runner.environment;
      expect(env, isNotNull, reason: 'Yosys was spawned with no environment');
      expect(env!['NO_COLOR'], '1');
      // Whatever PATH this process inherited, the package-manager
      // directories are on the one Yosys gets. The map carries PATH only
      // when it had to change it; otherwise the child inherits this
      // process's, which then already has them.
      final effective = env['PATH'] ?? Platform.environment['PATH'] ?? '';
      final path = splitSearchPath(effective);
      for (final dir in engineSearchDirs()) {
        expect(path, contains(dir));
      }
    });

    test('the version probe goes through the same environment', () async {
      await CdcEngine(
        processRunner: runner,
      ).detectVersion(const EngineBinaryConfig.system());
      expect(runner.environment?['NO_COLOR'], '1');
    });

    test(
      'an elaboration failure is a finding marked as an analysis failure',
      () async {
        final violations = await CdcEngine(
          processRunner: runner,
          tempDirectory: temp,
        ).run(_request()).toList();
        final v = violations.single;
        expect(v.ruleId, 'cdc/elaboration-failed');
        expect(v.severity, Severity.error);
        expect(v.message, contains('unexpected TOK_ID'));
        expect(
          v.isAnalysisFailure,
          isTrue,
          reason:
              'The headless runner fails the run on this marker; without it a '
              'CI job reads an unelaborated design as one error, or as clean.',
        );
      },
    );
  });
}
