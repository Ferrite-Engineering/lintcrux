// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/rohd/rohd_sidecar.dart';

import '../../support/rohd_fixture_package.dart';

RohdSidecar _real() => parseRohdSidecar(
  File('$kRohdFixtureDir/Top.flc.json').readAsStringSync(),
).sidecar!;

RohdSymbol _symbol(RohdSidecar s, String module, String name) => s.modules
    .firstWhere((m) => m.name == module)
    .symbols
    .firstWhere((x) => x.name == name);

void main() {
  group('parseRohdSidecar — real ROHD output', () {
    final sidecar = _real();

    test('reads the files table and the generated modules', () {
      expect(sidecar.files, ['.dart_tool/../lib/design.dart']);
      expect(sidecar.packageRoot, '/work/rohd_fixture');
      expect(
        sidecar.modules.map((m) => m.name),
        containsAll(<String>['Top', 'Adder', 'Reg', 'Combinational']),
      );
    });

    test('a module written to a file names it; inline modules do not', () {
      final top = sidecar.modules.firstWhere((m) => m.name == 'Top');
      expect(top.svFileNames, ['Top.sv']);
      final comb = sidecar.modules.firstWhere((m) => m.name == 'Combinational');
      expect(comb.svFileNames, isEmpty);
    });

    test('a signal keeps every generated position, in order', () {
      final gated = _symbol(sidecar, 'Top', 'gated');
      expect(gated.positions.map((x) => x.line), [51, 54, 43]);
      expect(gated.isInstance, isFalse);
      // One Dart frame: where Top's constructor made it.
      expect(gated.frames.map((f) => f.toString()), ['0:59:19']);
    });

    test('frames run outermost first, so the last is the innermost', () {
      final sum = _symbol(sidecar, 'Top', 'sum');
      expect(sum.frames.map((f) => f.toString()), ['0:58:19', '0:24:15']);
      expect(sum.frames.last.line, 24);
    });

    test('an instance is marked and its position is kept', () {
      final adder = _symbol(sidecar, 'Top', 'adder');
      expect(adder.isInstance, isTrue);
      expect(adder.positions.single.line, 61);
      expect(adder.frames.map((f) => f.line), [58, 21]);
    });

    test('a renamed struct field keeps its Dart name', () {
      final valid = _symbol(sidecar, 'Top', 'inner_pkt_valid');
      expect(valid.original, 'valid');
      expect(valid.positions.map((x) => x.line), [63, 45]);
    });

    test('the older bare LINE:COL position is read', () {
      final clk = _symbol(sidecar, 'Top', 'clk');
      expect(clk.positions.single.line, 35);
      expect(clk.positions.single.column, 13);
    });

    test('a leaf with no position is kept but has none', () {
      final c = _symbol(sidecar, 'Top', "1'h1");
      expect(c.positions, isEmpty);
    });
  });

  group('parseRohdSidecar — what it refuses', () {
    test('an unknown version is unusable, with the version in the reason', () {
      final result = parseRohdSidecar(
        '{"version": 7, "files": [], "modules": {}}',
      );
      expect(result.sidecar, isNull);
      expect(result.problem, contains('version 7'));
      expect(result.problem, contains('version 6'));
    });

    test('a missing version is unusable', () {
      final result = parseRohdSidecar('{"files": []}');
      expect(result.sidecar, isNull);
      expect(result.problem, contains('no version'));
    });

    test('text that is not JSON, or not an object, is unusable', () {
      expect(parseRohdSidecar('').sidecar, isNull);
      expect(parseRohdSidecar('{"version":').sidecar, isNull);
      expect(parseRohdSidecar('[6]').sidecar, isNull);
      expect(parseRohdSidecar('[6]').problem, isNotEmpty);
    });

    test('wrong types inside a version 6 file are skipped, not thrown', () {
      final result = parseRohdSidecar(
        jsonEncode({
          'version': 6,
          'files': ['a.dart', 3, null],
          'packageRoot': 5,
          'modules': {
            'Bad': 'not a map',
            'Worse': {'outputFiles': 7, 'tree': 'nope'},
            'Odd': {
              'outputFiles': {
                'sv': [1, '/x/Odd.sv'],
              },
              'tree': <Object>[
                'a string',
                <Object>[],
                <Object>[5],
                ['not:a:frame:x', 'x@sv:1:1'],
                ['0:1:1', 'ok@sv:2:3', 'bad@sv:x:y', 'sc@sc:4:5', 9, '@sv:1:1'],
              ],
            },
          },
        }),
      );
      final s = result.sidecar!;
      expect(s.files, ['a.dart']);
      expect(s.packageRoot, isNull);
      final odd = s.modules.firstWhere((m) => m.name == 'Odd');
      expect(odd.svFileNames, ['Odd.sv']);
      expect(odd.symbols.map((x) => x.name), ['ok', 'bad', 'sc']);
      expect(odd.symbols.first.positions.single.line, 2);
      // `sc:` is SystemC; `x:y` is not numbers.
      expect(odd.symbols.skip(1).every((x) => x.positions.isEmpty), isTrue);
    });

    test('a tree nested far deeper than any real one does not overflow', () {
      var node = '["0:1:1","leaf@sv:1:1"]';
      for (var i = 0; i < 5000; i++) {
        node = '["0:1:1",$node]';
      }
      final result = parseRohdSidecar(
        '{"version":6,"files":[],"modules":{"M":{"tree":[$node]}}}',
      );
      expect(result.sidecar, isNotNull);
    });
  });
}
