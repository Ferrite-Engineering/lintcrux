// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/services/project/project_file_codec.dart';
import 'package:lintcrux/services/project/project_file_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ProjectFileService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lintcrux_project_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('write + read round-trips a project on disk', () async {
      const service = ProjectFileService();
      const project = LintProject(
        name: 'soc',
        rootPath: '/work/soc',
        sourceFiles: ['/work/soc/top.sv'],
        enabledEngineIds: ['verilator', 'verible'],
      );
      final path = p.join(tempDir.path, 'project.lintcrux');
      await service.write(path, project);
      expect(File(path).existsSync(), isTrue);
      final loaded = await service.read(path);
      expect(loaded, project);
    });

    test('read throws ProjectFileException for missing file', () async {
      const service = ProjectFileService();
      final missing = p.join(tempDir.path, 'does_not_exist.lintcrux');
      await expectLater(
        service.read(missing),
        throwsA(isA<ProjectFileException>()),
      );
    });

    test(
      'read throws ProjectFileException for malformed JSON on disk',
      () async {
        const service = ProjectFileService();
        final path = p.join(tempDir.path, 'bad.lintcrux');
        await File(path).writeAsString('{not json');
        await expectLater(
          service.read(path),
          throwsA(isA<ProjectFileException>()),
        );
      },
    );

    test('write overwrites an existing file', () async {
      const service = ProjectFileService();
      const a = LintProject(name: 'first', rootPath: '/r');
      const b = LintProject(name: 'second', rootPath: '/r');
      final path = p.join(tempDir.path, 'project.lintcrux');
      await service.write(path, a);
      await service.write(path, b);
      final loaded = await service.read(path);
      expect(loaded.name, 'second');
    });

    test('defaults to a usable ProjectFileCodec', () {
      const service = ProjectFileService();
      expect(service.codec, isNotNull);
    });
  });
}
