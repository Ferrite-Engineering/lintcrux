// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/constraints/constraints_engine.dart';
import 'package:path/path.dart' as p;

// The engine around the checks: what it does before it asks Yosys for
// anything, what it does with each way Yosys can end, and that it never
// reports "did not run" as a pass.

/// A fake Yosys. It writes [json] where the script's `write_json` points and
/// exits with [exitCode]; [spawns] counts the runs.
class _FakeYosys implements ProcessRunner {
  _FakeYosys({this.json, this.exitCode = 0, this.stderr = ''});

  final String? json;
  final int exitCode;
  final String stderr;
  int spawns = 0;

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
    spawns++;
    if (arguments.length >= 3 && arguments[0] == '-q' && arguments[1] == '-p') {
      final match = RegExp('write_json "([^"]+)"').firstMatch(arguments[2]);
      final data = json;
      if (match != null && data != null && exitCode == 0) {
        File(match.group(1)!).writeAsStringSync(data);
      }
    }
    return ProcessRunResult(exitCode: exitCode, stdout: '', stderr: stderr);
  }
}

String _topJson() => jsonEncode(<String, Object?>{
  'modules': <String, Object?>{
    'top': <String, Object?>{
      'attributes': <String, Object?>{
        'top': '00000000000000000000000000000001',
      },
      'ports': <String, Object?>{
        'clk': {
          'direction': 'input',
          'bits': [2],
        },
        'led': {
          'direction': 'output',
          'bits': [3, 4],
        },
      },
      'netnames': <String, Object?>{
        'clk': {
          'bits': [2],
          'attributes': {'src': 'top.v:3.5-3.8'},
        },
        'led': {
          'bits': [3, 4],
          'attributes': {'src': 'top.v:4.5-4.8'},
        },
      },
    },
  },
});

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('constraints_engine_'));
  tearDown(() => dir.deleteSync(recursive: true));

  String write(String name, String text) {
    final path = p.join(dir.path, name);
    File(path).writeAsStringSync(text);
    return path;
  }

  LintRunRequest request({
    List<String>? constraints,
    String? top = 'top',
    List<String> dropped = const <String>[],
  }) => LintRunRequest(
    sourceFiles: [p.join(dir.path, 'top.v')],
    droppedSources: dropped,
    binary: const EngineBinaryConfig.system(),
    language: HdlLanguage.verilog,
    topModule: top,
    projectRoot: dir.path,
    constraintFiles: constraints ?? const <String>[],
  );

  Future<List<Violation>> run(LintRunRequest r, _FakeYosys yosys) =>
      ConstraintsEngine(
        processRunner: yosys,
        tempDirectory: dir,
      ).run(r).toList();

  test('the engine declares what it is', () {
    final engine = ConstraintsEngine();
    expect(engine.id, 'constraints');
    expect(engine.capabilities.cacheable, isFalse);
    expect(engine.capabilities.supportedLanguages, {
      HdlLanguage.verilog,
      HdlLanguage.systemVerilog,
    });
  });

  test('no constraint files: no finding and no Yosys run', () async {
    final yosys = _FakeYosys();
    expect(await run(request(), yosys), isEmpty);
    expect(yosys.spawns, 0);
  });

  test(
    'constraint files and no top module: did not run, exit-3 marker',
    () async {
      final pins = write('pins.pcf', 'set_io clk 1\n');
      final yosys = _FakeYosys();
      final v = (await run(
        request(constraints: [pins], top: null),
        yosys,
      )).single;
      expect(v.ruleId, 'constraints/no-top-module');
      expect(v.severity, Severity.error);
      expect(v.isAnalysisFailure, isTrue);
      expect(v.location.file, pins);
      expect(yosys.spawns, 0);
    },
  );

  test('an empty top module name is no top module', () async {
    final pins = write('pins.pcf', 'set_io clk 1\n');
    final v = (await run(
      request(constraints: [pins], top: ''),
      _FakeYosys(),
    )).single;
    expect(v.ruleId, 'constraints/no-top-module');
  });

  test(
    'sources the engine does not read: did not run, no elaboration',
    () async {
      final pins = write('pins.pcf', 'set_io clk 1\n');
      final yosys = _FakeYosys();
      final v = (await run(
        request(constraints: [pins], dropped: ['pkg.vhd']),
        yosys,
      )).single;
      expect(v.ruleId, 'constraints/unsupported-sources');
      expect(v.isAnalysisFailure, isTrue);
      expect(v.message, contains('pkg.vhd'));
      expect(yosys.spawns, 0);
    },
  );

  group('a constraint file that cannot be read', () {
    test('missing', () async {
      final yosys = _FakeYosys(json: _topJson());
      final v = (await run(
        request(constraints: [p.join(dir.path, 'gone.pcf')]),
        yosys,
      )).single;
      expect(v.ruleId, 'constraints/constraint-file-unreadable');
      expect(v.isAnalysisFailure, isTrue);
      expect(v.message, contains('does not exist'));
      expect(yosys.spawns, 0, reason: 'a bad file costs no elaboration');
    });

    test('a directory', () async {
      final sub = Directory(p.join(dir.path, 'pins.pcf'))..createSync();
      final v = (await run(
        request(constraints: [sub.path]),
        _FakeYosys(json: _topJson()),
      )).single;
      expect(v.ruleId, 'constraints/constraint-file-unreadable');
      expect(v.message, contains('not a regular file'));
    });

    test('an extension that is none of the three', () async {
      final pins = write('pins.sdc', 'x');
      final v = (await run(
        request(constraints: [pins]),
        _FakeYosys(json: _topJson()),
      )).single;
      expect(v.ruleId, 'constraints/constraint-file-unreadable');
      expect(v.message, contains('.pcf, .lpf, .cst'));
    });

    test('over the size bound', () async {
      final pins = p.join(dir.path, 'big.pcf');
      final raf = File(pins).openSync(mode: FileMode.write)
        ..truncateSync(kMaxConstraintFileBytes + 1)
        ..closeSync();
      expect(raf, isNotNull);
      final yosys = _FakeYosys(json: _topJson());
      final v = (await run(request(constraints: [pins]), yosys)).single;
      expect(v.ruleId, 'constraints/constraint-file-unreadable');
      expect(v.message, contains('larger than'));
      expect(yosys.spawns, 0);
    });
  });

  group('elaboration', () {
    test("a design Yosys rejects: did not run, with Yosys's text", () async {
      final pins = write('pins.pcf', 'set_io clk 1\n');
      final v = (await run(
        request(constraints: [pins]),
        _FakeYosys(exitCode: 1, stderr: 'ERROR: syntax error near ;'),
      )).single;
      expect(v.ruleId, 'constraints/elaboration-failed');
      expect(v.isAnalysisFailure, isTrue);
      expect(v.message, contains('syntax error near ;'));
    });

    test('a Yosys that cannot be started is an engine failure, never a '
        'finding', () async {
      final pins = write('pins.pcf', 'set_io clk 1\n');
      final runner = _ThrowingRunner();
      expect(
        ConstraintsEngine(
          processRunner: runner,
          tempDirectory: dir,
        ).run(request(constraints: [pins])).toList(),
        throwsA(isA<EngineNotAvailableException>()),
      );
    });

    test('a netlist without the top module: did not run', () async {
      final pins = write('pins.pcf', 'set_io clk 1\n');
      final v = (await run(
        request(constraints: [pins], top: 'other'),
        _FakeYosys(json: '{"modules": {"x": {}}}'),
      )).single;
      expect(v.ruleId, 'constraints/elaboration-failed');
      expect(v.isAnalysisFailure, isTrue);
      expect(v.message, contains('`other`'));
    });
  });

  group('findings', () {
    test('sit on the constraint file line and column, port declarations on '
        'the RTL', () async {
      final pins = write(
        'pins.pcf',
        'set_io clk 1\nset_io  ledd[0] 2\nset_io led[9] 3\n',
      );
      final violations = await run(
        request(constraints: [pins]),
        _FakeYosys(json: _topJson()),
      );
      final byRule = {for (final v in violations) v.ruleId: v};
      expect(byRule.keys, {
        'constraints/unknown-port',
        'constraints/bit-out-of-range',
        'constraints/unconstrained-port',
      });

      final unknown = byRule['constraints/unknown-port']!;
      expect(unknown.location.file, pins);
      expect(unknown.location.line, 2);
      expect(unknown.location.column, 9);
      expect(unknown.severity, Severity.error);
      expect(unknown.message, contains('Did you mean `led`?'));
      expect(unknown.isAnalysisFailure, isFalse);

      final range = byRule['constraints/bit-out-of-range']!;
      expect(range.location.line, 3);

      final unconstrained = byRule['constraints/unconstrained-port']!;
      expect(unconstrained.severity, Severity.warning);
      expect(unconstrained.location.file, 'top.v');
      expect(unconstrained.location.line, 4);
    });

    test('a clean design and file produce no finding', () async {
      final pins = write(
        'pins.pcf',
        'set_io clk 1\nset_io led[0] 2\nset_io led[1] 3\n',
      );
      final v = await run(
        request(constraints: [pins]),
        _FakeYosys(json: _topJson()),
      );
      expect(v, isEmpty);
    });

    test('Yosys is asked for the top module of the request', () async {
      final pins = write('pins.pcf', 'set_io clk 1\n');
      final recorder = _RecordingRunner(_topJson());
      await ConstraintsEngine(
        processRunner: recorder,
        tempDirectory: dir,
      ).run(request(constraints: [pins])).toList();
      expect(recorder.script, contains('hierarchy -check -top top'));
      expect(
        recorder.script,
        isNot(contains('flatten')),
        reason: 'the ports of the top module need no flattening',
      );
    });
  });
}

class _ThrowingRunner implements ProcessRunner {
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
  }) async => throw ProcessException(executable, arguments, 'not found');
}

class _RecordingRunner extends _FakeYosys {
  _RecordingRunner(String json) : super(json: json);

  String script = '';

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
  }) {
    if (arguments.length >= 3) script = arguments[2];
    return super.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }
}
