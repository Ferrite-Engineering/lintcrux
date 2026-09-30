// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/services/import/edam_import_service.dart';
import 'package:lintcrux/services/import/edam_reader.dart';
import 'package:lintcrux/services/project/project_file_codec.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('edam-import-');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  File writeEdam(String content, {String name = 'design.eda.yml'}) =>
      File(p.join(tmp.path, name))..writeAsStringSync(content);

  const servShaped = '''
version: 0.2.1
name: award-winning_serv_serv_1.4.0
toplevel: serv_rf_top
tool_options:
  verilator:
    mode: lint-only
    verilator_options:
    - -Wall
files:
- {file_type: vlt, name: src/serv/data/verilator_waiver.vlt, core: 'award-winning:serv:serv:1.4.0'}
- {file_type: verilogSource, name: src/serv/rtl/serv_top.v, core: 'award-winning:serv:serv:1.4.0'}
''';

  group('EdamImportService', () {
    test('writes the .lintcrux beside the EDAM, stripping the .eda.yml '
        'double extension', () {
      final edam = writeEdam(servShaped);
      const service = EdamImportService();
      final result = service.importEdam(edamPath: edam.path);

      expect(result.projectFilePath, p.join(tmp.path, 'design.lintcrux'));
      expect(File(result.projectFilePath).existsSync(), isTrue);
      expect(result.sourceEdamPath, p.normalize(p.absolute(edam.path)));

      // The emitted file round-trips through the codec.
      final decoded = const ProjectFileCodec().decode(
        File(result.projectFilePath).readAsStringSync(),
      );
      expect(decoded.name, 'award-winning_serv_serv_1.4.0');
      expect(decoded.rootPath, tmp.path);
      expect(decoded.topModule, 'serv_rf_top');
      expect(decoded.language, HdlLanguage.verilog);
      expect(decoded.sourceFiles, [
        p.normalize(p.join(tmp.path, 'src/serv/rtl/serv_top.v')),
      ]);
      expect(
        decoded.sourceFileProvenance[decoded.sourceFiles.single],
        'award-winning:serv:serv:1.4.0',
      );
      expect(decoded.perEngineOptions['verilator'], {
        'warnFlags': ['all'],
        'waiverFiles': [
          p.normalize(p.join(tmp.path, 'src/serv/data/verilator_waiver.vlt')),
        ],
      });
    });

    test('honors an explicit outputPath and projectName', () {
      final edam = writeEdam(servShaped);
      final out = p.join(tmp.path, 'custom.lintcrux');
      const service = EdamImportService();
      final result = service.importEdam(
        edamPath: edam.path,
        outputPath: out,
        projectName: 'my_project',
      );
      expect(result.projectFilePath, out);
      expect(result.project.name, 'my_project');
      expect(File(out).existsSync(), isTrue);
    });

    // A project that cannot be written threw a bare FileSystemException,
    // which no caller catches: the menu import did nothing, and the command
    // line crashed instead of exiting 65.
    test('an output that cannot be written is an import error', () {
      final edam = writeEdam(servShaped);
      final blocker = File(p.join(tmp.path, 'blocker'))..writeAsStringSync('');
      const service = EdamImportService();
      expect(
        () => service.importEdam(
          edamPath: edam.path,
          outputPath: p.join(blocker.path, 'design.lintcrux'),
        ),
        throwsA(
          isA<EdamImportException>().having(
            (e) => e.message,
            'message',
            contains('could not write'),
          ),
        ),
      );
    });

    test('passes enabledEngineIds through', () {
      final edam = writeEdam(servShaped);
      const service = EdamImportService();
      final result = service.importEdam(
        edamPath: edam.path,
        enabledEngineIds: const ['verilator'],
      );
      expect(result.project.enabledEngineIds, ['verilator']);
    });

    test('omits the verilator options bag entirely when the EDAM carries '
        'nothing for it', () {
      final edam = writeEdam('''
version: 0.2.1
name: plain
files:
- {file_type: verilogSource, name: top.v}
''');
      const service = EdamImportService();
      final result = service.importEdam(edamPath: edam.path);
      expect(result.project.perEngineOptions, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('surfaces reader warnings on the result', () {
      final edam = writeEdam('''
version: 0.9.9
name: warny
files:
- {file_type: verilogSource, name: top.v}
- {file_type: tclSource, name: c.tcl}
''');
      const service = EdamImportService();
      final result = service.importEdam(edamPath: edam.path);
      expect(result.warnings, hasLength(2));
    });

    test('falls back to the EDAM basename when name is absent', () {
      final edam = writeEdam('''
version: 0.2.1
files:
- {file_type: verilogSource, name: top.v}
''', name: 'my_design.eda.yml');
      const service = EdamImportService();
      final result = service.importEdam(edamPath: edam.path);
      expect(result.project.name, 'my_design');
      expect(result.projectFilePath, p.join(tmp.path, 'my_design.lintcrux'));
    });
  });
}
