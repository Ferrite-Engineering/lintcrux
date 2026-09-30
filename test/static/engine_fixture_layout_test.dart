// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/os_detritus.dart';

/// Static guardrail: no loose fixture files may sit
/// directly under `test/fixtures/engines/<engine>/` (or the
/// `verification/` mirror). Every `output.txt` / `expected.sarif.json` /
/// `cmdline.txt` / `PROVENANCE.md` must live inside a `generated/<case>/`
/// or `captured/<case>/` directory, so the corpus layout is self-describing
/// and a stray hand-dropped file can't masquerade as a fixture.
const _fixtureRoots = <String>[
  'test/fixtures/engines',
  'verification/fixtures/engines',
];

const _allowedKinds = <String>{'generated', 'captured'};

void main() {
  test('every engine fixture lives under generated/ or captured/<case>/', () {
    final offenders = <String>[];
    for (final rootPath in _fixtureRoots) {
      final root = Directory(rootPath);
      if (!root.existsSync()) continue;
      for (final entity in root.listSync()) {
        // Opening the corpus in Finder is not a corpus defect.
        if (isOsDetritus(p.basename(entity.path))) continue;
        if (entity is! Directory) {
          offenders.add('${p.relative(entity.path)} (loose file at root)');
          continue;
        }
        final engineDir = entity;
        // helpers/ holds READMEs, not fixtures — skip it.
        if (p.basename(engineDir.path) == 'helpers') continue;
        for (final kindEntity in engineDir.listSync()) {
          final kind = p.basename(kindEntity.path);
          if (isOsDetritus(kind)) continue;
          if (kindEntity is! Directory) {
            offenders.add(
              '${p.relative(kindEntity.path)} (loose file under '
              '${p.basename(engineDir.path)}/)',
            );
            continue;
          }
          if (!_allowedKinds.contains(kind)) {
            offenders.add(
              '${p.relative(kindEntity.path)} (kind must be '
              'generated/ or captured/)',
            );
            continue;
          }
          // Inside generated/ or captured/, files must be nested one more
          // level in a <case>/ directory.
          for (final child in kindEntity.listSync()) {
            if (isOsDetritus(p.basename(child.path))) continue;
            if (child is! Directory) {
              offenders.add(
                '${p.relative(child.path)} (loose file under $kind/ — '
                'must be in a <case>/ subdirectory)',
              );
            }
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'engine fixtures must follow '
          '<engine>/{generated,captured}/<case>/<file>:\n  '
          '${offenders.join('\n  ')}',
    );
  });
}
