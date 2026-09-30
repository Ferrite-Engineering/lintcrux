// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Static guardrail: every captured engine fixture
/// must be attributed in its directory's `PROVENANCE.md` with a license
/// from the permissive allow-list. Captured outputs are rebuilt from public
/// OSS RTL; the allow-list keeps the corpus compatible with the
/// closed-source Pro distribution and blocks GPL/AGPL/proprietary
/// contamination. Mirrors the open-core decoder guard.
///
/// There are no captured engine fixtures yet, so this guard passes
/// vacuously today — it is in place so the *first* captured fixture cannot
/// land without attribution.
const _fixtureRoots = <String>[
  'test/fixtures/engines',
  'verification/fixtures/engines',
];

/// SPDX identifiers permitted for captured fixtures (shared with the
/// open-core decoder allow-list).
const _allowedLicenses = <String>{
  'MIT',
  'BSD-2-Clause',
  'BSD-3-Clause',
  'Apache-2.0',
  'ISC',
  'CC0-1.0',
  'public-domain',
};

Iterable<File> _provenanceFiles() sync* {
  for (final rootPath in _fixtureRoots) {
    final root = Directory(rootPath);
    if (!root.existsSync()) continue;
    for (final entity in root.listSync(recursive: true).whereType<File>()) {
      if (p.basename(entity.path) == 'PROVENANCE.md' &&
          entity.path.contains('${p.separator}captured${p.separator}')) {
        yield entity;
      }
    }
  }
}

void main() {
  test('every captured PROVENANCE.md license is on the allow-list', () {
    final offenders = <String>[];
    for (final provenance in _provenanceFiles()) {
      final body = provenance.readAsStringSync();
      final matches = RegExp(
        r'SPDX:\s*`?([A-Za-z0-9.\-]+)`?',
      ).allMatches(body);
      if (matches.isEmpty) {
        offenders.add('${p.relative(provenance.path)}: no SPDX license found');
        continue;
      }
      for (final m in matches) {
        final spdx = m.group(1)!.trim();
        if (!_allowedLicenses.contains(spdx)) {
          offenders.add(
            '${p.relative(provenance.path)}: SPDX `$spdx` not in allow-list',
          );
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'captured fixtures must use a permissive license '
          '($_allowedLicenses):\n  ${offenders.join('\n  ')}',
    );
  });
}
