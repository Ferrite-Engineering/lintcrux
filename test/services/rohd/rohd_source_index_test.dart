// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/rohd_dart_source.dart';
import 'package:lintcrux/services/rohd/rohd_sidecar.dart';
import 'package:lintcrux/services/rohd/rohd_source_index.dart';

import '../../support/rohd_fixture_package.dart';

final List<RohdFixturePackage> _packages = <RohdFixturePackage>[];

RohdFileIndex _real({required bool sidecar, bool perModule = false}) {
  final pkg = RohdFixturePackage.create(sidecar: sidecar, perModule: perModule);
  _packages.add(pkg);
  final svName = perModule ? 'Top.sv' : 'top.sv';
  final sv = pkg.inBuild(svName);
  final sidecars = <RohdSidecar>[];
  final dirs = <String>[];
  if (sidecar) {
    sidecars.add(
      parseRohdSidecar(
        File(pkg.inBuild('Top.flc.json')).readAsStringSync(),
      ).sidecar!,
    );
    dirs.add(pkg.build);
  }
  return RohdFileIndex.build(
    svPath: sv,
    lines: File(sv).readAsLinesSync(),
    sidecars: sidecars,
    sidecarDirs: dirs,
  );
}

String _loc(RohdDartLocation l) =>
    '${l.file.split('/').last}:${l.line}:${l.column}';

void main() {
  tearDownAll(() {
    for (final p in _packages) {
      p.dispose();
    }
  });

  group('with the sidecar — single file', () {
    final index = _real(sidecar: true);

    test('a declaration is exact', () {
      final s = index.lookup(43)!;
      expect(s.kind, RohdDartSourceKind.exact);
      expect(s.symbol, 'gated');
      expect(_loc(s.primary), 'design.dart:59:19');
      expect(s.fromInlineComment, isFalse);
    });

    test('a driving assignment inside always_comb is exact', () {
      final s = index.lookup(54)!; // gated = sum;
      expect(s.kind, RohdDartSourceKind.exact);
      expect(s.symbol, 'gated');
    });

    test('an instance is exact, with the instantiation as its caller', () {
      final s = index.lookup(61)!; // Adder adder(...)
      expect(s.kind, RohdDartSourceKind.exact);
      expect(s.symbol, 'adder');
      expect(_loc(s.primary), 'design.dart:21:29');
      expect(s.calledFrom.map(_loc), ['design.dart:58:19']);
    });

    test('a read has no symbol and falls back to the enclosing block', () {
      final s = index.lookup(53)!; // if(valid_bit) begin
      expect(s.kind, RohdDartSourceKind.enclosing);
      expect(s.symbol, 'combinational');
      expect(_loc(s.primary), 'design.dart:60:5');
    });

    test("every line to the block's end is enclosed, the next is not", () {
      for (final line in [52, 53, 55, 56, 57, 58, 59]) {
        expect(
          index.lookup(line)?.symbol,
          anyOf('combinational', 'gated'),
          reason: 'line $line',
        );
      }
      // Line 60 is blank between the block and the instance.
      expect(index.lookup(60), isNull);
    });

    test(
      'a line the trace knows nothing about, and the file header, are null',
      () {
        expect(index.lookup(1), isNull);
        expect(index.lookup(2), isNull);
        expect(index.lookup(64), isNull);
        expect(index.lookup(9999), isNull);
        expect(index.lookup(0), isNull);
      },
    );

    test("the finding's message chooses between symbols on one line", () {
      // Line 17 of Adder in the single file is where `partial` and the carry
      // are both driven: the adder's expression.
      final partial = index.lookup(17, message: "Signal 'partial' is driven");
      final carry = index.lookup(17, message: 'Signal _a_add_b_carry unused');
      final neither = index.lookup(17, message: 'something else');
      expect(partial!.symbol, 'partial');
      expect(carry!.symbol, '_a_add_b_carry');
      expect(neither, isNotNull);
    });

    test('the Dart path is normalized and resolved to the package', () {
      final s = index.lookup(43)!;
      expect(s.primary.file, endsWith('/lib/design.dart'));
      expect(s.primary.file, isNot(contains('.dart_tool')));
      expect(File(s.primary.file).existsSync(), isTrue);
    });
  });

  group('with the sidecar — one module per file', () {
    final index = _real(sidecar: true, perModule: true);

    test('a read inside the block maps to the combinational block', () {
      final s = index.lookup(20)!; // if(valid_bit) begin
      expect(s.kind, RohdDartSourceKind.enclosing);
      expect(s.symbol, 'combinational');
    });

    test('a driver maps exactly', () {
      final s = index.lookup(21)!; // gated = sum;
      expect(s.kind, RohdDartSourceKind.exact);
      expect(_loc(s.primary), 'design.dart:59:19');
    });
  });

  group('inline comments only', () {
    final index = _real(sidecar: false);

    test('a commented line is exact and says where it came from', () {
      final s = index.lookup(61)!;
      expect(s.kind, RohdDartSourceKind.exact);
      expect(s.fromInlineComment, isTrue);
      expect(_loc(s.primary), 'design.dart:21:29');
      expect(s.calledFrom.map(_loc), ['design.dart:58:19']);
    });

    test('a read inside always_comb falls back to the comment above it', () {
      final s = index.lookup(53)!;
      expect(s.kind, RohdDartSourceKind.enclosing);
      expect(s.fromInlineComment, isTrue);
      expect(_loc(s.primary), 'design.dart:60:5');
    });

    test('an uncommented declaration has nothing to fall back to', () {
      expect(index.lookup(47), isNull); // logic valid_bit;
    });
  });

  group('extents on hand-made SystemVerilog', () {
    RohdFileIndex build(List<String> lines, Map<String, Object> tree) {
      final dir = Directory.systemTemp.createTempSync('lintcrux_rohd_idx_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final sidecar = parseRohdSidecar(
        jsonEncode({
          'version': 6,
          'files': ['lib/m.dart'],
          'modules': {
            'M': {
              'outputFiles': {
                'sv': ['m.sv'],
              },
              'tree': [tree['tree']],
            },
          },
        }),
      ).sidecar!;
      return RohdFileIndex.build(
        svPath: '${dir.path}/m.sv',
        lines: lines,
        sidecars: [sidecar],
        sidecarDirs: [dir.path],
      );
    }

    test('lines of a multi-line instance port list belong to the instance', () {
      final index = build(
        [
          'module M;', // 1
          'Sub  u (', // 2
          '  .a(x),', // 3
          '  .b(y)', // 4
          ');', // 5
          'assign z = 1;', // 6
          'endmodule', // 7
        ],
        {
          'tree': ['0:10:3', '*u@2:1'],
        },
      );
      expect(index.lookup(2)!.kind, RohdDartSourceKind.exact);
      for (final line in [3, 4, 5]) {
        final s = index.lookup(line)!;
        expect(s.kind, RohdDartSourceKind.enclosing, reason: 'line $line');
        expect(s.symbol, 'u');
      }
      expect(index.lookup(6), isNull);
    });

    test('a case statement and else branches are followed to their end', () {
      final index = build(
        [
          'module M;', // 1
          '// comb', // 2
          'always_comb begin', // 3
          '  case (sel)', // 4
          '    1: y = a;', // 5
          '    default: y = b;', // 6
          '  endcase', // 7
          'end', // 8
          'assign q = 0;', // 9
          'endmodule', // 10
        ],
        {
          'tree': ['0:7:7', '*comb@2:1'],
        },
      );
      for (final line in [4, 5, 6, 7, 8]) {
        expect(index.lookup(line)?.symbol, 'comb', reason: 'line $line');
      }
      expect(index.lookup(9), isNull);
    });

    test('an unterminated block does not run away', () {
      final lines = <String>[
        'module M;',
        'always_comb begin',
        for (var i = 0; i < 5000; i++) '  x = $i;',
      ];
      final index = build(lines, {
        'tree': ['0:1:1', '*b@2:1'],
      });
      expect(index.lookup(10)?.symbol, 'b');
      expect(index.lookup(4500), isNull, reason: 'past the follow limit');
    });
  });

  group('which file a sidecar applies to', () {
    RohdSidecar sidecar(List<String> files) => parseRohdSidecar(
      jsonEncode({
        'version': 6,
        'files': ['lib/m.dart'],
        'modules': {
          for (final f in files)
            f: {
              'outputFiles': {
                'sv': ['$f.sv'],
              },
              'tree': [
                ['0:1:1', 'sig_$f@sv:2:1'],
              ],
            },
        },
      }),
    ).sidecar!;

    RohdFileIndex build(String sv, RohdSidecar s) => RohdFileIndex.build(
      svPath: sv,
      lines: ['module m;', 'logic x;', 'endmodule'],
      sidecars: [s],
      sidecarDirs: [Directory.systemTemp.path],
    );

    test('only modules written to this file count', () {
      final s = sidecar(['A', 'B']);
      expect(build('/x/A.sv', s).lookup(2)!.symbol, 'sig_A');
      expect(build('/x/b.sv', s).lookup(2)!.symbol, 'sig_B');
    });

    test('a renamed file matches a sidecar that describes one file', () {
      expect(build('/x/renamed.sv', sidecar(['A'])).lookup(2)!.symbol, 'sig_A');
    });

    test('a file of another name with several candidates matches none', () {
      expect(build('/x/renamed.sv', sidecar(['A', 'B'])).lookup(2), isNull);
    });
  });
}
