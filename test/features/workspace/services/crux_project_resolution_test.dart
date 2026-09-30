// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/workspace/services/crux_project_resolution.dart';
import 'package:path/path.dart' as p;

/// LintCrux's half of the `<design>.crux-project` contract.
void main() {
  const resolver = CruxProjectResolver();

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('lc_crux_project'));
  tearDown(() => tmp.deleteSync(recursive: true));

  ({String manifest, String dir}) writeDesign(
    String yaml, {
    List<String> files = const <String>[],
    String manifestName = 'design.crux-project',
  }) {
    final dir = Directory(p.join(tmp.path, 'design'))
      ..createSync(recursive: true);
    for (final f in files) {
      File(p.join(dir.path, f))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('');
    }
    final manifest = p.join(dir.path, manifestName);
    File(manifest).writeAsStringSync(yaml);
    return (manifest: manifest, dir: dir.path);
  }

  test('an ordinary .lintcrux path passes through untouched', () {
    final r = resolver.resolve('/d/project.lintcrux');
    expect(r, isA<NotAManifest>());
    expect((r as NotAManifest).path, '/d/project.lintcrux');
  });

  test('a named manifest resolves to its lint project and design id', () {
    final d = writeDesign(
      'version: 1\nname: uart\nartifacts:\n  lint: project.lintcrux\n',
      files: ['project.lintcrux'],
    );
    final r = resolver.resolve(d.manifest);
    expect(r, isA<ManifestLintProject>());
    final lp = r as ManifestLintProject;
    expect(lp.lintProjectPath, endsWith('project.lintcrux'));
    expect(lp.displayName, 'uart');
    expect(lp.designId, cxpDesignIdForPath(d.dir));
    expect(lp.legacyRenameTo, isNull);
  });

  test('the legacy bare .crux-project still resolves, with the same design '
      'id, and names the file to rename it to', () {
    final d = writeDesign(
      'version: 1\nname: uart\nartifacts:\n  lint: project.lintcrux\n',
      files: ['project.lintcrux'],
      manifestName: '.crux-project',
    );
    final r = resolver.resolve(d.manifest);
    expect(r, isA<ManifestLintProject>());
    final lp = r as ManifestLintProject;
    expect(lp.lintProjectPath, endsWith('project.lintcrux'));
    expect(lp.designId, cxpDesignIdForPath(d.dir));
    expect(lp.legacyRenameTo, 'design.crux-project');
  });

  test('a folder holding two manifests is refused, naming both', () {
    final d = writeDesign(
      'version: 1\nartifacts:\n  lint: project.lintcrux\n',
      files: ['project.lintcrux'],
    );
    File(p.join(d.dir, '.crux-project')).writeAsStringSync('version: 1\n');

    final r = resolver.resolve(d.manifest);

    expect(r, isA<ManifestAmbiguous>());
    final error = (r as ManifestAmbiguous).error;
    expect(error.candidates.map(p.basename), [
      '.crux-project',
      'design.crux-project',
    ]);
    expect(p.equals(error.directory, d.dir), isTrue);
  });

  test('a manifest with no lint entry says what to add', () {
    // The normal state for a design that has a dump but no lint project yet.
    final d = writeDesign(
      'version: 1\nname: uart\nartifacts:\n  waveform: sim/u.vcd\n',
    );
    final r = resolver.resolve(d.manifest);
    expect(r, isA<ManifestUnusable>());
    final m = (r as ManifestUnusable).message;
    expect(m, contains('uart'));
    expect(m, contains('lint'));
    expect(m, contains('design.crux-project'));
  });

  test('a named-but-missing lint project names the path', () {
    final d = writeDesign(
      'version: 1\nartifacts:\n  lint: gone.lintcrux\n',
    );
    final r = resolver.resolve(d.manifest);
    expect(r, isA<ManifestUnusable>());
    expect((r as ManifestUnusable).message, contains('gone.lintcrux'));
  });

  test('a lint entry may name a directory, not just a file', () {
    // The spec allows either; the planner's existence check covers both.
    final d = writeDesign('version: 1\nartifacts:\n  lint: lint/\n');
    Directory(p.join(d.dir, 'lint')).createSync(recursive: true);
    expect(resolver.resolve(d.manifest), isA<ManifestLintProject>());
  });

  test('an invalid manifest is reported, not opened', () {
    final d = writeDesign('name: no version\n');
    final r = resolver.resolve(d.manifest);
    expect(r, isA<ManifestUnusable>());
    expect((r as ManifestUnusable).message, contains('version'));
  });

  group('isOpenableProjectPath', () {
    test('a .lintcrux project and a design manifest open', () {
      expect(isOpenableProjectPath('/d/project.lintcrux'), isTrue);
      expect(isOpenableProjectPath('/d/uart_tx.crux-project'), isTrue);
      expect(isOpenableProjectPath('/d/my.crux-project'), isTrue);
      expect(isOpenableProjectPath('uart_tx.crux-project'), isTrue);
    });

    test('the extension is matched case-insensitively', () {
      expect(isOpenableProjectPath('/d/Uart_TX.CRUX-PROJECT'), isTrue);
    });

    test('the legacy bare .crux-project still opens', () {
      expect(isOpenableProjectPath('/d/.crux-project'), isTrue);
      expect(isOpenableProjectPath('.crux-project'), isTrue);
    });

    test('anything else does not', () {
      expect(isOpenableProjectPath('/d/top.sv'), isFalse);
      expect(isOpenableProjectPath('/d/notes.crux-project.txt'), isFalse);
      expect(isOpenableProjectPath('/d/crux-project'), isFalse);
    });
  });

  group('suggestedManifestFileName', () {
    test('names the manifest after its directory', () {
      expect(
        suggestedManifestFileName('/work/uart_tx'),
        'uart_tx.crux-project',
      );
      expect(
        suggestedManifestFileName('/work/uart_tx/'),
        'uart_tx.crux-project',
      );
    });

    test('falls back to design when the directory has no name', () {
      expect(suggestedManifestFileName('/'), 'design.crux-project');
    });
  });
}
