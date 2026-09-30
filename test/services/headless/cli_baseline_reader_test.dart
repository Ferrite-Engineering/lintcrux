// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/baseline_violation.dart';
import 'package:lintcrux/domain/models/lint_baseline.dart';
import 'package:lintcrux/services/headless/cli_baseline_reader.dart';
import 'package:path/path.dart' as p;

void main() {
  const reader = CliBaselineReader();

  // `resolvePath` normalizes, so a rooted path spelled with `/` comes back
  // in the host separator: `/repo` on POSIX, `\repo` on Windows. Spell the
  // root the same way the resolver will so the expectations are host-shaped.
  final root = p.normalize('/repo');

  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lintcrux_baseline_');
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('resolvePath', () {
    test('defaults to .lintcrux-baseline.json in the project root', () {
      expect(
        CliBaselineReader.resolvePath(projectRoot: root),
        p.join(root, '.lintcrux-baseline.json'),
      );
    });

    test('the default filename matches what the Pro store writes', () {
      // If these ever diverge, the Pro app writes a baseline the CI gate
      // never finds and every gated build silently reports everything as
      // new. Pinned here on purpose.
      expect(CliBaselineReader.defaultFileName, '.lintcrux-baseline.json');
    });

    test('an explicit path wins and is absolutized', () {
      final resolved = CliBaselineReader.resolvePath(
        projectRoot: root,
        explicitPath: 'ci/base.json',
      );
      expect(p.isAbsolute(resolved), isTrue);
      expect(resolved, endsWith(p.join('ci', 'base.json')));
    });

    test('an empty explicit path falls back to the default', () {
      expect(
        CliBaselineReader.resolvePath(projectRoot: root, explicitPath: ''),
        p.join(root, '.lintcrux-baseline.json'),
      );
    });
  });

  group('read', () {
    test('a missing file is not an error — just no baseline', () async {
      final result = await reader.read(p.join(tmp.path, 'nope.json'));
      expect(result.hasBaseline, isFalse);
      expect(result.isCorrupt, isFalse);
      expect(result.baseline, isNull);
    });

    test('parses a baseline the Pro store would have written', () async {
      final path = p.join(tmp.path, '.lintcrux-baseline.json');
      final baseline = LintBaseline(
        baselineId: 'cli-1',
        createdAt: DateTime.utc(2026, 7, 21),
        createdBy: 'ci',
        projectPath: tmp.path,
        frozenViolations: const <BaselineViolation>[
          BaselineViolation(
            fingerprint: 'abc123',
            ruleId: 'verilator/WIDTHTRUNC',
            filePath: '/repo/top.sv',
            line: 7,
            message: 'truncation',
          ),
        ],
      );
      File(path).writeAsStringSync(jsonEncode(baseline.toJson()));

      final result = await reader.read(path);
      expect(result.hasBaseline, isTrue);
      expect(result.baseline!.baselineId, 'cli-1');
      expect(result.baseline!.frozenCount, 1);
      expect(result.baseline!.fingerprintSet, contains('abc123'));
    });

    test('invalid JSON is reported, not thrown', () async {
      final path = p.join(tmp.path, 'b.json');
      File(path).writeAsStringSync('{ not json');
      final result = await reader.read(path);
      expect(result.isCorrupt, isTrue);
      expect(result.hasBaseline, isFalse);
    });

    test('a JSON array is reported', () async {
      final path = p.join(tmp.path, 'b.json');
      File(path).writeAsStringSync('[]');
      final result = await reader.read(path);
      expect(result.isCorrupt, isTrue);
      expect(result.error, contains('JSON object'));
    });

    test('an unknown schema version is reported', () async {
      // Forward-compatibility: a newer Pro build's baseline must be
      // refused loudly rather than half-interpreted.
      final path = p.join(tmp.path, 'b.json');
      File(path).writeAsStringSync(
        jsonEncode(<String, Object?>{
          'version': 99,
          'baselineId': 'x',
          'createdAt': '2026-01-01T00:00:00Z',
          'projectPath': '/repo',
          'frozenViolations': <Object?>[],
        }),
      );
      final result = await reader.read(path);
      expect(result.isCorrupt, isTrue);
      expect(result.error, contains('99'));
    });

    test('a missing required field is reported', () async {
      final path = p.join(tmp.path, 'b.json');
      File(path).writeAsStringSync(
        jsonEncode(<String, Object?>{'version': LintBaseline.currentVersion}),
      );
      final result = await reader.read(path);
      expect(result.isCorrupt, isTrue);
    });

    test('the returned path is always echoed back', () async {
      final path = p.join(tmp.path, 'anything.json');
      expect((await reader.read(path)).path, path);
    });
  });
}
