// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/services/engines/cdc/cdc_engine.dart';

// CDC's only process is Yosys. A machine without Yosys must report the CDC
// engine as unavailable — never as a completed run carrying an error finding,
// which a gate would pass on and a baseline could freeze.

/// A process runner scripted per test: either every spawn fails the way a
/// missing executable does, or it returns [result] — after writing
/// [jsonBytes] to the script's `write_json` path, when given.
class _ScriptedProcessRunner implements ProcessRunner {
  _ScriptedProcessRunner.missing() : result = null, jsonBytes = null;
  _ScriptedProcessRunner.exits(
    ProcessRunResult this.result, {
    this.jsonBytes,
  });

  final ProcessRunResult? result;
  final List<int>? jsonBytes;
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
    final r = result;
    if (r == null) {
      throw ProcessException(
        executable,
        arguments,
        'No such file or directory',
      );
    }
    final bytes = jsonBytes;
    if (bytes != null && arguments.length >= 3) {
      final match = RegExp('write_json "([^"]+)"').firstMatch(arguments[2]);
      if (match != null) await File(match.group(1)!).writeAsBytes(bytes);
    }
    return r;
  }
}

LintRunRequest _request({
  EngineBinaryConfig binary = const EngineBinaryConfig.system(),
  List<String> sourceFiles = const <String>['/tmp/top.v'],
}) => LintRunRequest(
  sourceFiles: sourceFiles,
  binary: binary,
  language: HdlLanguage.verilog,
  topModule: 'top',
);

void main() {
  test('a yosys that cannot be started makes CDC unavailable', () async {
    final engine = CdcEngine(processRunner: _ScriptedProcessRunner.missing());
    await expectLater(
      engine.run(_request()),
      emitsError(isA<EngineNotAvailableException>()),
    );
  });

  test('a yosys killed by its time budget is a timed-out engine', () async {
    final engine = CdcEngine(
      processRunner: _ScriptedProcessRunner.exits(
        const ProcessRunResult(
          exitCode: -9,
          stdout: '',
          stderr: '',
          termination: ProcessTermination.timedOut,
        ),
      ),
    );
    await expectLater(
      engine.run(_request()),
      emitsError(isA<EngineTimedOutException>()),
    );
  });

  test('a genuine elaboration error on the RTL is still a finding', () async {
    final engine = CdcEngine(
      processRunner: _ScriptedProcessRunner.exits(
        const ProcessRunResult(
          exitCode: 1,
          stdout: '',
          stderr: "ERROR: Module `missing' is not part of the design.",
        ),
      ),
    );
    final violations = await engine.run(_request()).toList();
    expect(violations.single.ruleId, 'cdc/elaboration-failed');
  });

  // The other YosysFailureKinds are about the tool, not the design: each one
  // fails the engine rather than yielding cdc/elaboration-failed.

  test('a request Yosys was never handed fails the engine', () async {
    final runner = _ScriptedProcessRunner.exits(
      const ProcessRunResult(exitCode: 0, stdout: '', stderr: ''),
    );
    await expectLater(
      CdcEngine(
        processRunner: runner,
      ).run(_request(sourceFiles: const <String>['/tmp/to"p.v'])),
      emitsError(
        isA<EngineRunFailedException>().having(
          (e) => e.reason,
          'reason',
          contains('could not be turned into a yosys script'),
        ),
      ),
    );
    expect(runner.executables, isEmpty);
  });

  test('a Yosys JSON output that cannot be read fails the engine', () async {
    await expectLater(
      CdcEngine(
        processRunner: _ScriptedProcessRunner.exits(
          const ProcessRunResult(exitCode: 0, stdout: '', stderr: ''),
          jsonBytes: const <int>[0xFF, 0xFE, 0xFD],
        ),
      ).run(_request()),
      emitsError(
        isA<EngineRunFailedException>().having(
          (e) => e.reason,
          'reason',
          contains('could not be read back'),
        ),
      ),
    );
  });

  test('a clean Yosys exit with no JSON output fails the engine', () async {
    // Not an elaboration error on the RTL: as cdc/elaboration-failed it would
    // be a finding a baseline could freeze, for a run that elaborated nothing.
    await expectLater(
      CdcEngine(
        processRunner: _ScriptedProcessRunner.exits(
          const ProcessRunResult(exitCode: 0, stdout: '', stderr: ''),
        ),
      ).run(_request()),
      emitsError(
        isA<EngineRunFailedException>().having(
          (e) => e.exitCode,
          'exitCode',
          0,
        ),
      ),
    );
  });

  test('CDC runs the Yosys binary the request configures', () async {
    final runner = _ScriptedProcessRunner.missing();
    final engine = CdcEngine(processRunner: runner);
    await expectLater(
      engine.run(
        _request(
          binary: const EngineBinaryConfig(
            source: EngineBinarySource.custom,
            path: '/opt/y/bin/yosys',
          ),
        ),
      ),
      emitsError(
        isA<EngineNotAvailableException>().having(
          (e) => e.resolvedPath,
          'resolvedPath',
          '/opt/y/bin/yosys',
        ),
      ),
    );
    expect(runner.executables, ['/opt/y/bin/yosys']);
  });

  test('detectVersion probes the configured Yosys binary', () async {
    final runner = _ScriptedProcessRunner.missing();
    final version = await CdcEngine(processRunner: runner).detectVersion(
      const EngineBinaryConfig(
        source: EngineBinarySource.custom,
        path: '/opt/y/bin/yosys',
      ),
    );
    expect(version, isNull);
    expect(runner.executables, ['/opt/y/bin/yosys']);
  });
}
