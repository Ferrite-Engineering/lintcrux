// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/services/engines/yosys/yosys_elaboration.dart';
import 'package:path/path.dart' as p;

// The shared elaboration helper: the ports of the top module, read from the
// raw `write_json` document because crux_netlist's Port drops the declared
// index range and the declaration's source position.

String _doc({
  String top = 'top',
  Map<String, Object?>? ports,
  Map<String, Object?>? netnames,
  Object? topAttribute = '00000000000000000000000000000001',
}) => jsonEncode(<String, Object?>{
  'modules': <String, Object?>{
    'helper': <String, Object?>{
      'attributes': <String, Object?>{},
      'ports': <String, Object?>{},
    },
    top: <String, Object?>{
      'attributes': <String, Object?>{'top': topAttribute},
      'ports': ports ?? <String, Object?>{},
      'netnames': netnames ?? <String, Object?>{},
    },
  },
});

void main() {
  group('readTopModulePorts', () {
    test('width, direction, offset, upto and declaration come from the '
        'netname', () {
      final ports = readTopModulePorts(
        _doc(
          ports: {
            'clk': {
              'direction': 'input',
              'bits': [2],
            },
            'a': {
              'direction': 'output',
              'bits': [3, 4, 5, 6],
            },
            'b': {
              'direction': 'input',
              'bits': [7, 8],
            },
          },
          netnames: {
            'clk': {
              'bits': [2],
              'attributes': {'src': 'top.v:3.23-3.26'},
            },
            'a': {
              'bits': [3, 4, 5, 6],
              'offset': 1,
              'attributes': {'src': 'top.v:6.23-6.24'},
            },
            'b': {
              'bits': [7, 8],
              'upto': 1,
              'attributes': <String, Object?>{},
            },
          },
        ),
        'top',
      )!;
      final clk = ports.singleWhere((x) => x.name == 'clk');
      expect((clk.width, clk.direction, clk.isBus), (1, 'input', false));
      expect(clk.declaration?.line, 3);
      expect(clk.declaration?.column, 23);

      final a = ports.singleWhere((x) => x.name == 'a');
      // [4:1]
      expect(a.indexes, [4, 3, 2, 1]);
      expect(a.hasIndex(1), isTrue);
      expect(a.hasIndex(0), isFalse);
      expect(a.hasIndex(5), isFalse);

      final b = ports.singleWhere((x) => x.name == 'b');
      // [0:1]
      expect(b.indexes, [0, 1]);
      expect(b.declaration, isNull);
    });

    test('the module is found by the top attribute when the name is not '
        'there', () {
      final ports = readTopModulePorts(
        _doc(
          top: r'$paramod\top',
          ports: {
            'x': {
              'direction': 'input',
              'bits': [2],
            },
          },
        ),
        'top',
      );
      expect(ports?.single.name, 'x');
    });

    test('null for a document with no such module, or not write_json', () {
      expect(readTopModulePorts(_doc(topAttribute: 0), 'nope'), isNull);
      expect(readTopModulePorts('not json', 'top'), isNull);
      expect(readTopModulePorts('[]', 'top'), isNull);
      expect(readTopModulePorts('{"modules": 3}', 'top'), isNull);
    });
  });

  group('against a real Yosys', () {
    final yosys = _yosysOnPath();
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('elaborate_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test(
      '[7:0], [0:7], [8:1] and a scalar resolve to their declared indexes',
      () async {
        final src = File(p.join(dir.path, 'top.v'))
          ..writeAsStringSync('''
module top (
  input  wire        clk,
  output wire [7:0]  down,
  output wire [0:7]  up,
  output wire [8:1]  shifted,
  input  wire [0:0]  one
);
  assign down = 8'd0;
  assign up = 8'd0;
  assign shifted = 8'd0;
endmodule
''');
        final request = LintRunRequest(
          sourceFiles: [src.path],
          binary: const EngineBinaryConfig.system(),
          language: HdlLanguage.verilog,
          topModule: 'top',
          projectRoot: dir.path,
        );
        final result = await elaborateDesign(
          request,
          engineId: 'constraints',
          processRunner: const DefaultProcessRunner(),
          tempDirectory: dir,
        );
        final ports = readTopModulePorts(
          (result as DesignElaborated).rawJson,
          'top',
        )!;
        ElaboratedPort port(String name) =>
            ports.singleWhere((x) => x.name == name);

        expect(port('clk').width, 1);
        expect(port('down').indexes, [7, 6, 5, 4, 3, 2, 1, 0]);
        expect(port('up').indexes, [0, 1, 2, 3, 4, 5, 6, 7]);
        expect(port('shifted').indexes, [8, 7, 6, 5, 4, 3, 2, 1]);
        expect(port('shifted').hasIndex(0), isFalse);
        expect(port('shifted').hasIndex(8), isTrue);
        expect(port('one').width, 1);
        expect(port('down').declaration?.line, 3);
        expect(port('shifted').declaration?.line, 5);
      },
      skip: yosys ? false : 'yosys not on PATH',
    );

    test(
      'a design Yosys rejects is a DesignElaborationFailed, not a throw',
      () async {
        final src = File(p.join(dir.path, 'bad.v'))
          ..writeAsStringSync('module top(;\n');
        final result = await elaborateDesign(
          LintRunRequest(
            sourceFiles: [src.path],
            binary: const EngineBinaryConfig.system(),
            language: HdlLanguage.verilog,
            topModule: 'top',
            projectRoot: dir.path,
          ),
          engineId: 'constraints',
          processRunner: const DefaultProcessRunner(),
          tempDirectory: dir,
        );
        expect(result, isA<DesignElaborationFailed>());
      },
      skip: yosys ? false : 'yosys not on PATH',
    );
  });
}

bool _yosysOnPath() {
  final pathVar = Platform.environment['PATH'] ?? '';
  final exe = Platform.isWindows ? 'yosys.exe' : 'yosys';
  for (final d in pathVar.split(Platform.isWindows ? ';' : ':')) {
    if (d.isEmpty) continue;
    if (File('$d${Platform.pathSeparator}$exe').existsSync()) return true;
  }
  return false;
}
