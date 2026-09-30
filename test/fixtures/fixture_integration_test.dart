// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/services/engines/slang/slang_engine.dart';
import 'package:lintcrux/services/engines/verible/verible_engine.dart';
import 'package:lintcrux/services/engines/verilator/verilator_engine.dart';
import 'package:lintcrux/services/project/project_file_codec.dart';
import 'package:path/path.dart' as p;

/// Cheap PATH probe — walks PATH segments and stats each candidate.
/// Used as the skip gate for the engine-binary integration tests.
bool _onPath(String binary) {
  final pathVar = Platform.environment['PATH'] ?? '';
  for (final dir in pathVar.split(Platform.isWindows ? ';' : ':')) {
    final candidate = File(p.join(dir, binary));
    if (candidate.existsSync()) return true;
  }
  return false;
}

class _FixtureCase {
  _FixtureCase({
    required this.name,
    required this.projectPath,
    required this.expectedSarifPath,
  });
  final String name;
  final String projectPath;
  final String expectedSarifPath;
}

List<_FixtureCase> _discover() {
  final root = p.join(
    Directory.current.path,
    'test',
    'fixtures',
    'projects',
  );
  final dir = Directory(root);
  if (!dir.existsSync()) return const [];
  final cases = <_FixtureCase>[];
  for (final entry in dir.listSync()) {
    if (entry is! Directory) continue;
    final project = File(p.join(entry.path, 'project.lintcrux'));
    final expected = File(p.join(entry.path, 'expected.sarif.json'));
    if (!project.existsSync() || !expected.existsSync()) continue;
    cases.add(
      _FixtureCase(
        name: p.basename(entry.path),
        projectPath: project.path,
        expectedSarifPath: expected.path,
      ),
    );
  }
  return cases;
}

void main() {
  group('Fixture corpus', () {
    final cases = _discover();

    test('discovered ≥ 3 hand-crafted fixture projects', () {
      expect(cases.length, greaterThanOrEqualTo(3));
      expect(
        cases.map((c) => c.name),
        containsAll(['basic_warnings', 'clean_project', 'multi_engine']),
      );
    });

    test('every fixture has a parseable .lintcrux project file', () {
      const codec = ProjectFileCodec();
      for (final c in cases) {
        final raw = File(c.projectPath).readAsStringSync();
        final project = codec.decode(raw);
        expect(project.name, isNotEmpty, reason: c.name);
        expect(project.sourceFiles, isNotEmpty, reason: c.name);
      }
    });

    // NOTE: this asserts SHAPE ONLY, and that is all it ever asserted.
    // For the corpus's whole life it was also the *only* test that opened
    // these files, which meant any syntactically valid SARIF passed —
    // including two goldens that disagreed with the real engines about
    // the rule ids, the line numbers and the message text. The assertion
    // that the content is real lives in
    // `project_fixture_golden_test.dart`; this one is kept only as a
    // cheap JSON well-formedness canary. Do not add expectations here
    // that belong in the golden test.
    test('every fixture has a parseable expected.sarif.json', () {
      for (final c in cases) {
        final raw = File(c.expectedSarifPath).readAsStringSync();
        final decoded = jsonDecode(raw);
        expect(decoded, isA<Map<String, dynamic>>(), reason: c.name);
        expect((decoded as Map)['version'], '2.1.0', reason: c.name);
      }
    });

    // Real-binary integration tests below skip when the engine isn't on
    // PATH. To run them locally:
    //   brew install verilator verible
    //   git clone --depth 1 https://github.com/MikePopoloski/slang && \
    //     cd slang && cmake -B build && cmake --build build
    //   PATH=$PWD/slang/build/bin:$PATH flutter test
    test(
      'VerilatorEngine.detectVersion against system verilator',
      () async {
        final engine = VerilatorEngine();
        final version = await engine.detectVersion(
          const EngineBinaryConfig.system(),
        );
        expect(version, isNotNull);
        expect(version!.toLowerCase(), contains('verilator'));
      },
      skip: _onPath('verilator') ? false : 'verilator not on PATH',
    );

    test(
      'VeribleEngine.detectVersion against system verible-verilog-lint',
      () async {
        final engine = VeribleEngine();
        final version = await engine.detectVersion(
          const EngineBinaryConfig.system(),
        );
        expect(version, isNotNull);
        expect(version!.trim(), isNotEmpty);
      },
      skip: _onPath('verible-verilog-lint')
          ? false
          : 'verible-verilog-lint not on PATH',
    );

    test(
      'SlangEngine.detectVersion against system slang',
      () async {
        final engine = SlangEngine();
        final version = await engine.detectVersion(
          const EngineBinaryConfig.system(),
        );
        expect(version, isNotNull);
        expect(version!.trim(), isNotEmpty);
      },
      skip: _onPath('slang') ? false : 'slang not on PATH',
    );
  });
}
