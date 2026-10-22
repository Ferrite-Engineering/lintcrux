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
import 'package:lintcrux/services/engines/cdc/cdc_engine.dart';
import 'package:path/path.dart' as p;

// How the CDC engine chooses its SystemVerilog reader, and what it says when
// it has no reader for the design.
//
// Yosys's built-in `read_verilog -sv` stops on package scoping and the other
// constructs every package-based design uses (OpenTitan, Ibex and CVA6 all
// stop in their packages), so CDC reads SystemVerilog with yosys-slang when
// the Yosys it runs has it. A Yosys without it (Homebrew's) gets one finding
// that names what is missing instead of a parser error.

/// A Yosys stand-in: answers the version and slang probes, records the
/// script and the slang command file, and either writes [json] where the
/// script asks or fails with [stderr].
class _FakeYosys implements ProcessRunner {
  _FakeYosys({required this.slang, this.json, this.stderr = ''});

  final bool slang;
  final String? json;
  final String stderr;

  int slangProbes = 0;
  String? script;
  String? commandFile;

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
    if (arguments.contains('help read_slang')) {
      slangProbes++;
      return ProcessRunResult(
        exitCode: 0,
        stdout: slang
            ? '    read_slang [options] <sources>\n'
            : 'ERROR: No such command or cell type: read_slang\n',
        stderr: '',
      );
    }
    if (arguments.length == 1 && arguments.single == '-V') {
      return const ProcessRunResult(
        exitCode: 0,
        stdout: 'Yosys 0.70',
        stderr: '',
      );
    }
    final s = arguments.last;
    script = s;
    final f = RegExp(r'read_slang -f ([^\s;]+)').firstMatch(s);
    if (f != null) commandFile = File(f.group(1)!).readAsStringSync();
    final out = RegExp('write_json "([^"]+)"').firstMatch(s);
    if (json != null && out != null) {
      File(out.group(1)!).writeAsStringSync(json!);
      return const ProcessRunResult(exitCode: 0, stdout: '', stderr: '');
    }
    return ProcessRunResult(exitCode: 1, stdout: '', stderr: stderr);
  }
}

/// A flattened two-domain netlist in the shape yosys-slang writes it: one
/// flop in clk_a drives one in clk_b directly, and every `src` file is
/// relative to the directory Yosys ran in. Written by hand; the crossing is
/// what the structure means, not what the engine says.
String _slangShapedJson() {
  Map<String, Object?> dff(int clk, int d, int q, String src) =>
      <String, Object?>{
        'hide_name': 0,
        'type': r'$dff',
        'parameters': <String, Object?>{'WIDTH': 1, 'CLK_POLARITY': 1},
        'attributes': <String, Object?>{'src': src},
        'port_directions': <String, Object?>{
          'CLK': 'input',
          'D': 'input',
          'Q': 'output',
        },
        'connections': <String, Object?>{
          'CLK': <Object>[clk],
          'D': <Object>[d],
          'Q': <Object>[q],
        },
      };
  Map<String, Object?> net(List<Object> bits) => <String, Object?>{
    'hide_name': 0,
    'bits': bits,
    'attributes': <String, Object?>{},
  };
  return jsonEncode(<String, Object?>{
    'creator': 'hand-written',
    'modules': <String, Object?>{
      'top': <String, Object?>{
        'attributes': <String, Object?>{'top': 1},
        'ports': <String, Object?>{
          'clk_a': <String, Object?>{
            'direction': 'input',
            'bits': <Object>[2],
          },
          'clk_b': <String, Object?>{
            'direction': 'input',
            'bits': <Object>[3],
          },
          'd': <String, Object?>{
            'direction': 'input',
            'bits': <Object>[4],
          },
          'q': <String, Object?>{
            'direction': 'output',
            'bits': <Object>[6],
          },
        },
        'cells': <String, Object?>{
          'flag_a': dff(2, 4, 5, 'rtl/top.sv:23.3-23.20'),
          'flag_b': dff(3, 5, 6, 'rtl/top.sv:28.3-28.20'),
        },
        'netnames': <String, Object?>{
          'clk_a': net(<Object>[2]),
          'clk_b': net(<Object>[3]),
          'd': net(<Object>[4]),
          'flag_a': net(<Object>[5]),
          'q': net(<Object>[6]),
        },
      },
    },
  });
}

void main() {
  late Directory temp;
  late String root;
  late String top;
  late String pkg;
  late String legacy;

  setUp(() {
    YosysAvailabilityService.resetSlangProbeCacheForTesting();
    temp = Directory.systemTemp.createTempSync('cdc-slang-');
    root = p.join(temp.path, 'project');
    top = p.join(root, 'rtl', 'top.sv');
    pkg = p.join(root, 'rtl', 'types_pkg.sv');
    legacy = p.join(root, 'rtl', 'legacy.v');
    File(top)
      ..createSync(recursive: true)
      ..writeAsStringSync(
        'module top\n  import types_pkg::*;\n(input logic clk);\nendmodule\n',
      );
    File(pkg).writeAsStringSync(
      '// types shared by both domains\n'
      'package types_pkg; // the one package\n'
      '  typedef logic [7:0] byte_t;\n'
      'endpackage\n',
    );
    File(legacy).writeAsStringSync('module legacy(input clk); endmodule\n');
  });

  tearDown(() {
    YosysAvailabilityService.resetSlangProbeCacheForTesting();
    temp.deleteSync(recursive: true);
  });

  LintRunRequest request(
    List<String> sources, {
    Map<String, Object?> options = const <String, Object?>{},
  }) => LintRunRequest(
    sourceFiles: sources,
    sourceLanguages: <String, HdlLanguage>{
      for (final s in sources)
        s: s.endsWith('.sv') ? HdlLanguage.systemVerilog : HdlLanguage.verilog,
    },
    includePaths: <String>[p.join(root, 'inc')],
    defines: const {'SYNTHESIS': ''},
    binary: const EngineBinaryConfig.system(),
    language: HdlLanguage.mixed,
    topModule: 'top',
    projectRoot: root,
    options: options,
  );

  Future<List<Violation>> run(
    _FakeYosys yosys,
    LintRunRequest request,
  ) => CdcEngine(
    processRunner: yosys,
    tempDirectory: temp,
  ).run(request).toList();

  group('the reader', () {
    test('SystemVerilog is read with yosys-slang when the Yosys has it, with '
        'the options CDC needs', () async {
      final yosys = _FakeYosys(slang: true, stderr: 'ERROR: stop here');
      await run(yosys, request([pkg, top]));
      expect(yosys.script, contains('read_slang -f '));
      expect(yosys.script, isNot(contains('read_verilog')));
      final lines = LineSplitter.split(yosys.commandFile!).toList();
      expect(lines, contains('--single-unit'));
      expect(lines, contains('--top top'));
      expect(lines, contains('--ignore-initial'));
      expect(lines, contains('--ignore-assertions'));
      expect(lines, contains('-D SYNTHESIS'));
      expect(lines, contains('-I "${p.join(root, 'inc')}"'));
      expect(lines, containsAllInOrder(<String>['"$pkg"', '"$top"']));
    });

    test('blackboxedModules adds one --blackboxed-module each', () async {
      final yosys = _FakeYosys(slang: true, stderr: 'ERROR: stop here');
      await run(
        yosys,
        request(
          [pkg, top],
          options: const {
            'blackboxedModules': ['rglts_pdm_3p3v', 'pad_macro'],
          },
        ),
      );
      final lines = LineSplitter.split(yosys.commandFile!).toList();
      expect(lines, contains('--blackboxed-module rglts_pdm_3p3v'));
      expect(lines, contains('--blackboxed-module pad_macro'));
    });

    test('a blackboxedModules entry that is not a module name fails the '
        'engine before Yosys starts', () async {
      final yosys = _FakeYosys(slang: true, stderr: 'ERROR: stop here');
      await expectLater(
        CdcEngine(processRunner: yosys, tempDirectory: temp).run(
          request(
            [pkg, top],
            options: const {
              'blackboxedModules': ['top; write_json /x'],
            },
          ),
        ),
        emitsError(isA<EngineRunFailedException>()),
      );
      expect(yosys.script, isNull, reason: 'Yosys must not be started');
    });

    test(
      'without yosys-slang, SystemVerilog falls back to read_verilog -sv',
      () async {
        final yosys = _FakeYosys(slang: false, stderr: 'ERROR: stop here');
        await run(yosys, request([pkg, top]));
        expect(yosys.script, contains('read_verilog -sv'));
        expect(yosys.script, isNot(contains('read_slang')));
      },
    );

    test(
      'a Verilog-only design keeps the built-in reader and never probes',
      () async {
        final yosys = _FakeYosys(slang: true, stderr: 'ERROR: stop here');
        await run(yosys, request([legacy]));
        expect(yosys.slangProbes, 0);
        expect(yosys.script, contains('read_verilog'));
        expect(yosys.script, isNot(contains('read_slang')));
      },
    );

    test(
      'the probe is asked once per Yosys binary, not once per run',
      () async {
        final yosys = _FakeYosys(slang: true, stderr: 'ERROR: stop here');
        await run(yosys, request([pkg, top]));
        await run(yosys, request([pkg, top]));
        expect(yosys.slangProbes, 1);
      },
    );
  });

  group('findings from a slang netlist', () {
    test('name the project file, not the path relative to the run '
        'directory', () async {
      final yosys = _FakeYosys(slang: true, json: _slangShapedJson());
      final violations = await run(yosys, request([pkg, top]));
      final crossing = violations.singleWhere(
        (v) => v.ruleId == 'cdc/unsync-single-bit',
      );
      expect(crossing.location.file, top);
      expect(crossing.location.line, 28);
      expect(crossing.relatedLocations.single.file, top);
      expect(crossing.relatedLocations.single.line, 23);
    });

    test('the summary says SystemVerilog was read with yosys-slang', () async {
      final yosys = _FakeYosys(slang: true, json: _slangShapedJson());
      final violations = await run(yosys, request([pkg, top]));
      final summary = violations.singleWhere((v) => v.ruleId == 'cdc/summary');
      expect(summary.message, contains('read with yosys-slang'));
    });
  });

  group('a design the reader refuses', () {
    test('without yosys-slang, a package-based design gets one finding that '
        'names the slang frontend and where to get it', () async {
      final yosys = _FakeYosys(
        slang: false,
        stderr:
            'some preamble\n'
            '$pkg:3: ERROR: syntax error, unexpected TOK_ID\n',
      );
      final violations = await run(yosys, request([pkg, top]));
      final v = violations.single;
      expect(v.ruleId, 'cdc/needs-slang-frontend');
      expect(v.severity, Severity.error);
      expect(v.isAnalysisFailure, isTrue);
      expect(v.location.file, pkg);
      expect(v.location.line, 2, reason: 'the package declaration');
      expect(v.message, contains('package types_pkg'));
      expect(v.message, contains('yosys-slang'));
      expect(v.message, contains('OSS CAD Suite'));
      expect(v.message, contains('unexpected TOK_ID'));
      expect(v.message, contains('--yosys-path'));
      expect(v.message, isNot(contains('—')), reason: 'no em dashes');
    });

    test(
      'an import is enough when the package is declared elsewhere',
      () async {
        final yosys = _FakeYosys(slang: false, stderr: 'ERROR: x');
        final violations = await run(yosys, request([top]));
        final v = violations.single;
        expect(v.ruleId, 'cdc/needs-slang-frontend');
        expect(v.location.file, top);
        expect(v.location.line, 2);
        expect(v.message, contains('import types_pkg::'));
      },
    );

    test('without yosys-slang and without packages it is an elaboration '
        'failure', () async {
      final plain = p.join(root, 'rtl', 'plain.sv');
      File(plain).writeAsStringSync('module plain; endmodule\n');
      final yosys = _FakeYosys(slang: false, stderr: 'ERROR: something else');
      final v = (await run(yosys, request([plain]))).single;
      expect(v.ruleId, 'cdc/elaboration-failed');
      expect(v.isAnalysisFailure, isTrue);
    });

    test('with yosys-slang, a refusal is an elaboration failure that says '
        'which reader refused', () async {
      final yosys = _FakeYosys(
        slang: true,
        stderr: 'ERROR: reading net state during design initialization',
      );
      final v = (await run(yosys, request([pkg, top]))).single;
      expect(v.ruleId, 'cdc/elaboration-failed');
      expect(v.message, contains('yosys-slang'));
      expect(v.message, contains('design initialization'));
      expect(v.isAnalysisFailure, isTrue);
    });
  });
}
