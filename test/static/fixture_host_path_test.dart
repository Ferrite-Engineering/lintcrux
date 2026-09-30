// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Static guardrail: no committed fixture may carry an absolute path from
/// the machine that produced it.
///
/// This is not hygiene. These trees are mirrored into a **public**
/// repository, so an absolute path here is published — it names a
/// developer's home directory and their local directory layout to
/// everybody who clones it.
/// It is also a correctness bug on its own: a golden whose bytes depend
/// on the checkout path only reproduces on the machine that cut it, which
/// is exactly how `test/fixtures/projects/*/expected.sarif.json` came to
/// hold `/Users/<name>/…` URIs that no other checkout could reproduce.
/// Paths in a fixture must be relative to the fixture.
const _roots = <String>[
  'test/fixtures',
  'examples',
  'verification/fixtures',
];

/// Extensions worth scanning. Binary fixtures are skipped — they hold no
/// paths we author, and reading them as UTF-8 is meaningless.
const _textExtensions = <String>{
  '.json',
  '.sarif',
  '.txt',
  '.lintcrux',
  '.md',
  '.sv',
  '.v',
  '.vhd',
  '.yaml',
};

/// Absolute-path shapes an engine or capture host can leak.
final _hostPathPatterns = <RegExp>[
  RegExp('/Users/[A-Za-z0-9._-]+/'),
  RegExp('/home/[A-Za-z0-9._-]+/'),
  RegExp(r'[A-Za-z]:\\Users\\'),
  RegExp('file:///'),
];

void main() {
  test('no committed fixture carries an absolute host path', () {
    final offenders = <String>[];
    for (final rootPath in _roots) {
      final root = Directory(rootPath);
      if (!root.existsSync()) continue;
      for (final file in root.listSync(recursive: true).whereType<File>()) {
        if (!_textExtensions.contains(p.extension(file.path))) continue;
        final String text;
        try {
          text = file.readAsStringSync();
        } on FileSystemException {
          continue;
        }
        for (final pattern in _hostPathPatterns) {
          final match = pattern.firstMatch(text);
          if (match != null) {
            offenders.add('${p.relative(file.path)}: "${match.group(0)}"');
            break;
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          "these fixtures embed the capture host's absolute paths. They "
          'are mirrored into the public beta repo by '
          'tool/publish_beta_fixtures.dart, and a golden built from them '
          'only reproduces on the machine that cut it. Rebase the paths '
          'onto the fixture directory:\n  ${offenders.join('\n  ')}',
    );
  });
}
