// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/services/import/filelist_import_service.dart';
import 'package:lintcrux/services/import/filelist_reader.dart';
import 'package:lintcrux/services/project/project_file_codec.dart';
import 'package:path/path.dart' as p;

void main() {
  group('FilelistImportService', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('filelist-import-');
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('produces a .lintcrux project beside the input by default', () {
      File(p.join(dir.path, 'rtl.f')).writeAsStringSync('''
+incdir+include
+define+WIDTH=8
top.sv
core/alu.sv
''');
      const service = FilelistImportService();
      final result = service.importFilelist(
        filelistPath: p.join(dir.path, 'rtl.f'),
      );
      expect(result.projectFilePath, endsWith('rtl.lintcrux'));
      expect(File(result.projectFilePath).existsSync(), isTrue);

      // Round-trip the emitted file through the codec to confirm it
      // matches the in-memory project.
      const codec = ProjectFileCodec();
      final reloaded = codec.decode(
        File(result.projectFilePath).readAsStringSync(),
      );
      expect(reloaded.name, 'rtl');
      expect(reloaded.rootPath, p.normalize(p.absolute(dir.path)));
      expect(reloaded.sourceFiles, hasLength(2));
      expect(reloaded.defines, {'WIDTH': '8'});
      expect(reloaded.includePaths, hasLength(1));
      expect(reloaded.language, HdlLanguage.systemVerilog);
    });

    test('honors an explicit output path and project name', () {
      File(p.join(dir.path, 'rtl.f')).writeAsStringSync('top.sv\n');
      const service = FilelistImportService();
      final outPath = p.join(dir.path, 'custom.lintcrux');
      final result = service.importFilelist(
        filelistPath: p.join(dir.path, 'rtl.f'),
        outputPath: outPath,
        projectName: 'custom-name',
      );
      expect(result.projectFilePath, outPath);
      expect(result.project.name, 'custom-name');
    });

    // A project that cannot be written (a read-only checkout, a vendor tree)
    // threw a bare FileSystemException, which no caller catches: the menu
    // import did nothing, and the command line crashed instead of exiting 65.
    test('an output that cannot be written is an import error', () {
      File(p.join(dir.path, 'rtl.f')).writeAsStringSync('top.sv\n');
      final blocker = File(p.join(dir.path, 'blocker'))..writeAsStringSync('');
      const service = FilelistImportService();
      expect(
        () => service.importFilelist(
          filelistPath: p.join(dir.path, 'rtl.f'),
          outputPath: p.join(blocker.path, 'rtl.lintcrux'),
        ),
        throwsA(
          isA<FilelistImportException>().having(
            (e) => e.message,
            'message',
            contains('could not write'),
          ),
        ),
      );
    });

    test('passes projectLanguage + enabledEngineIds through', () {
      File(p.join(dir.path, 'rtl.f')).writeAsStringSync('top.vhd\n');
      const service = FilelistImportService();
      final result = service.importFilelist(
        filelistPath: p.join(dir.path, 'rtl.f'),
        projectLanguage: HdlLanguage.vhdl,
        enabledEngineIds: const ['ghdl'],
      );
      expect(result.project.language, HdlLanguage.vhdl);
      expect(result.project.enabledEngineIds, ['ghdl']);
    });
  });
}
