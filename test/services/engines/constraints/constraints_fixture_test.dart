// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/services/engines/constraints/constraints_engine.dart';
import 'package:path/path.dart' as p;

// The live assertion for the constraints fixtures: the real engine, over a
// real Yosys, against expected.sarif.json.
//
// expected.sarif.json is written by hand from each constraint file (what the
// file gets wrong by construction), never from this engine's output or from
// nextpnr's. What nextpnr itself does with each file is recorded in the case's
// PROVENANCE.md and output.txt; this test does not run nextpnr (LintCrux's CI
// installs no nextpnr and has no engine canary).

const _root = 'verification/fixtures/engines/constraints/captured';
const _families = <String>['ice40', 'ecp5', 'gowin'];
const _cases = <String>[
  'clean',
  'unknown_port',
  'unconstrained_port',
  'bit_out_of_range',
  'pin_reused',
  'port_reassigned',
  'unparsed_line',
];

void main() {
  final root = Directory(_root);

  test('the fixture directory exists and holds every family and case', () {
    expect(root.existsSync(), isTrue, reason: '$_root is missing');
    final present = root
        .listSync()
        .whereType<Directory>()
        .map((d) => p.basename(d.path))
        .toSet();
    final expected = {
      for (final f in _families)
        for (final c in _cases) '${f}_$c',
    };
    expect(present, expected);
  });

  test('every case carries its inputs, its capture and its provenance', () {
    for (final dir in root.listSync().whereType<Directory>()) {
      final family = p.basename(dir.path).split('_').first;
      final ext = switch (family) {
        'ice40' => 'pcf',
        'ecp5' => 'lpf',
        _ => 'cst',
      };
      for (final name in <String>[
        'top.v',
        'pins.$ext',
        'output.txt',
        'expected.sarif.json',
        'PROVENANCE.md',
      ]) {
        expect(
          File(p.join(dir.path, name)).existsSync(),
          isTrue,
          reason: '${p.basename(dir.path)} is missing $name',
        );
      }
      final provenance = File(
        p.join(dir.path, 'PROVENANCE.md'),
      ).readAsStringSync();
      expect(provenance, contains('6b438a1c9ab83cfb872fea21d9545d7d0bb8573f'));
      expect(provenance, contains('What nextpnr does with it'));
      final capture = File(p.join(dir.path, 'output.txt')).readAsStringSync();
      expect(capture, contains('exit status:'));
    }
  });

  final yosys = _yosysOnPath();
  for (final family in _families) {
    for (final name in _cases) {
      final id = '${family}_$name';
      test(
        '$id: the engine reports what the file gets wrong, and nothing else',
        () async {
          final dir = Directory(p.join(_root, id));
          expect(dir.existsSync(), isTrue, reason: '${dir.path} is missing');
          final pins = dir
              .listSync()
              .whereType<File>()
              .map((f) => f.path)
              .map(p.absolute)
              .singleWhere((f) => p.basename(f).startsWith('pins.'));
          final top = p.absolute(dir.path, 'top.v');
          final violations = await ConstraintsEngine()
              .run(
                LintRunRequest(
                  sourceFiles: [top],
                  binary: const EngineBinaryConfig.system(),
                  language: HdlLanguage.verilog,
                  topModule: 'top',
                  projectRoot: p.absolute(dir.path),
                  constraintFiles: [pins],
                ),
              )
              .toList();

          final expected = _readExpected(
            File(p.join(dir.path, 'expected.sarif.json')),
          );

          String keyOf(String rule, String level, String file, int line) =>
              '$rule|$level|${p.basename(file)}|$line';
          final want = <String>[
            for (final e in expected) keyOf(e.rule, e.level, e.file, e.line),
          ]..sort();
          final got = <String>[
            for (final v in violations)
              keyOf(
                v.ruleId,
                _level(v.severity),
                v.location.file,
                v.location.line,
              ),
          ]..sort();
          expect(got, want);

          // Each finding names what the expectation says it must mention.
          for (final e in expected) {
            final v = violations.singleWhere(
              (x) => x.ruleId == e.rule && x.location.line == e.line,
            );
            for (final mention in e.mentions) {
              expect(
                v.message,
                contains(mention),
                reason: '$id ${e.rule} should mention "$mention"',
              );
            }
            expect(v.isAnalysisFailure, isFalse);
          }
        },
        skip: yosys ? false : 'yosys not on PATH',
      );
    }
  }
}

/// One result of an `expected.sarif.json`.
class _Expected {
  const _Expected(this.rule, this.level, this.file, this.line, this.mentions);

  final String rule;
  final String level;
  final String file;
  final int line;
  final List<String> mentions;
}

List<_Expected> _readExpected(File file) {
  final doc = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final run = (doc['runs']! as List<Object?>).single! as Map<String, Object?>;
  return <_Expected>[
    for (final raw in run['results']! as List<Object?>)
      _fromResult(raw! as Map<String, Object?>),
  ];
}

_Expected _fromResult(Map<String, Object?> result) {
  final location =
      (result['locations']! as List<Object?>).first! as Map<String, Object?>;
  final physical = location['physicalLocation']! as Map<String, Object?>;
  final artifact = physical['artifactLocation']! as Map<String, Object?>;
  final region = physical['region']! as Map<String, Object?>;
  final properties = result['properties']! as Map<String, Object?>;
  return _Expected(
    result['ruleId']! as String,
    result['level']! as String,
    artifact['uri']! as String,
    region['startLine']! as int,
    (properties['mentions']! as List<Object?>).cast<String>(),
  );
}

String _level(Severity s) => switch (s) {
  Severity.fatal || Severity.error => 'error',
  Severity.warning => 'warning',
  _ => 'note',
};

bool _yosysOnPath() {
  final pathVar = Platform.environment['PATH'] ?? '';
  final exe = Platform.isWindows ? 'yosys.exe' : 'yosys';
  for (final d in pathVar.split(Platform.isWindows ? ';' : ':')) {
    if (d.isEmpty) continue;
    if (File('$d${Platform.pathSeparator}$exe').existsSync()) return true;
  }
  return false;
}
