// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/rohd_dart_source.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/rohd/rohd_source_loader.dart';
import 'package:lintcrux/services/transformers/rohd_source_transformer.dart';

import '../../support/rohd_fixture_package.dart';

Violation _finding(String file, int line, {String message = 'unused signal'}) =>
    Violation(
      engineId: 'verilator',
      ruleId: 'verilator/UNUSEDSIGNAL',
      severity: Severity.warning,
      message: message,
      location: SourceLocation(file: file, line: line, column: 1),
    );

void main() {
  late RohdFixturePackage pkg;
  late RohdSourceTransformer transformer;
  late String sv;

  setUp(() async {
    pkg = RohdFixturePackage.create();
    sv = pkg.inBuild('top.sv');
    final maps = await loadRohdSourceMaps(
      sourceFiles: [sv],
      projectRoot: pkg.root,
    );
    transformer = RohdSourceTransformer(maps.byFile);
  });
  tearDown(() => pkg.dispose());

  test('adds the Dart source and leaves the SystemVerilog location alone', () {
    final v = transformer.transform(_finding(sv, 54));
    final source = RohdDartSource.fromRaw(v.raw)!;
    expect(source.primary.file, pkg.path('lib/design.dart'));
    expect(source.primary.line, 59);
    expect(v.location.file, sv);
    expect(v.location.line, 54);
  });

  test('a read gets the enclosing block', () {
    final source = RohdDartSource.fromRaw(
      transformer.transform(_finding(sv, 53)).raw,
    )!;
    expect(source.kind, RohdDartSourceKind.enclosing);
    expect(source.primary.line, 60);
  });

  test('the value is plain JSON, so it survives a SARIF round trip', () {
    final v = transformer.transform(_finding(sv, 61));
    final copy = jsonDecode(jsonEncode(v.raw)) as Map<String, dynamic>;
    expect(RohdDartSource.fromRaw(copy)!.primary.line, 21);
    expect(RohdDartSource.fromRaw(copy)!.calledFrom.single.line, 58);
  });

  test('keeps what was already in raw', () {
    final base = _finding(sv, 54).copyWith(raw: {'lintcrux.x': 1});
    expect(transformer.transform(base).raw['lintcrux.x'], 1);
  });

  test(
    'a finding in another file, an unknown line or no file is untouched',
    () {
      for (final v in <Violation>[
        _finding('/somewhere/else.sv', 54),
        _finding(sv, 1),
        _finding('', 54),
      ]) {
        expect(identical(transformer.transform(v), v), isTrue);
      }
    },
  );

  test('the empty transformer is a no-op', () {
    final v = _finding(sv, 54);
    expect(identical(RohdSourceTransformer.empty.transform(v), v), isTrue);
  });

  test('a mangled value in raw reads as no Dart source', () {
    expect(RohdDartSource.fromRaw({RohdDartSource.rawKey: 'x'}), isNull);
    expect(
      RohdDartSource.fromRaw({
        RohdDartSource.rawKey: {
          'primary': {'file': 'a', 'line': 0},
        },
      }),
      isNull,
    );
    expect(RohdDartSource.fromRaw(const {}), isNull);
  });
}
