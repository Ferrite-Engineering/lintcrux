// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Static guardrail: fixture-companion completeness.
///
///  - every `generated/<case>/output.txt` has a sibling
///    `expected.sarif.json` (the golden) and a `cmdline.txt` (provenance of
///    what produced the output);
///  - every `captured/<case>/output.txt` has a sibling
///    `expected.sarif.json` and a `PROVENANCE.md`.
///
/// This stops a half-committed corpus case (a golden with no input, or an
/// input with no golden) from silently rotting.
const _fixtureRoots = <String>[
  'test/fixtures/engines',
  'verification/fixtures/engines',
];

Iterable<Directory> _caseDirs(String kind) sync* {
  for (final rootPath in _fixtureRoots) {
    final root = Directory(rootPath);
    if (!root.existsSync()) continue;
    for (final engineDir in root.listSync().whereType<Directory>()) {
      if (p.basename(engineDir.path) == 'helpers') continue;
      final kindDir = Directory('${engineDir.path}/$kind');
      if (!kindDir.existsSync()) continue;
      yield* kindDir.listSync().whereType<Directory>();
    }
  }
}

void main() {
  test(
    'every generated case has output.txt + expected.sarif.json + cmdline.txt',
    () {
      final problems = <String>[];
      for (final caseDir in _caseDirs('generated')) {
        for (final required in const <String>[
          'output.txt',
          'expected.sarif.json',
          'cmdline.txt',
        ]) {
          if (!File('${caseDir.path}/$required').existsSync()) {
            problems.add('${p.relative(caseDir.path)} is missing $required');
          }
        }
      }
      expect(problems, isEmpty, reason: problems.join('\n  '));
    },
  );

  test(
    'every captured case has output.txt + expected.sarif.json + PROVENANCE.md',
    () {
      final problems = <String>[];
      for (final caseDir in _caseDirs('captured')) {
        for (final required in const <String>[
          'output.txt',
          'expected.sarif.json',
          'PROVENANCE.md',
        ]) {
          if (!File('${caseDir.path}/$required').existsSync()) {
            problems.add('${p.relative(caseDir.path)} is missing $required');
          }
        }
      }
      expect(problems, isEmpty, reason: problems.join('\n  '));
    },
  );
}
