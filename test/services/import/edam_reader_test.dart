// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/models/project_source_file.dart';
import 'package:lintcrux/services/import/edam_reader.dart';
import 'package:path/path.dart' as p;

/// Mirrors the reader's own resolution so assertions stay OS-agnostic
/// (`p.normalize(p.join(...))` differs from string concatenation on
/// Windows).
String _resolved(String baseDir, String relative) =>
    p.normalize(p.join(baseDir, relative));

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('edam-reader-');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  File writeEdam(String content, {String name = 'design.eda.yml'}) =>
      File(p.join(tmp.path, name))..writeAsStringSync(content);

  group('EdamReader', () {
    test('reads the SERV-shaped lint EDAM: sources, toplevel, vlt waiver, '
        'tool options, provenance', () {
      final edam = writeEdam('''
version: 0.2.1
name: award-winning_serv_serv_1.4.0
toplevel: serv_rf_top
parameters:
  W:
    datatype: int
    paramtype: vlogparam
    description: Internal datapath width (1=SERV, 4=QERV)
tool_options:
  verilator:
    mode: lint-only
    verilator_options:
    - -Wall
filters: []
flow_options: {}
hooks: {}
files:
- {file_type: vlt, name: src/serv/data/verilator_waiver.vlt, core: 'award-winning:serv:serv:1.4.0'}
- {file_type: verilogSource, name: src/serv/rtl/serv_bufreg.v, core: 'award-winning:serv:serv:1.4.0'}
- {file_type: verilogSource, name: src/serv/rtl/serv_top.v, core: 'award-winning:serv:serv:1.4.0'}
vpi: []
''');
      final imported = const EdamReader().read(edam.path);

      expect(imported.name, 'award-winning_serv_serv_1.4.0');
      expect(imported.version, '0.2.1');
      expect(imported.toplevel, 'serv_rf_top');
      expect(imported.sourceFiles, [
        _resolved(tmp.path, 'src/serv/rtl/serv_bufreg.v'),
        _resolved(tmp.path, 'src/serv/rtl/serv_top.v'),
      ]);
      expect(imported.language, HdlLanguage.verilog);
      expect(
        imported.sourceFileLanguages[_resolved(
          tmp.path,
          'src/serv/rtl/serv_top.v',
        )],
        ProjectSourceFileLanguage.verilog,
      );
      expect(
        imported.sourceFileProvenance[_resolved(
          tmp.path,
          'src/serv/rtl/serv_top.v',
        )],
        'award-winning:serv:serv:1.4.0',
      );
      // `-Wall` → warnFlags ['all']; the `.vlt` rides the waiver
      // channel, not the source list.
      expect(imported.verilatorWarnFlags, ['all']);
      expect(imported.verilatorWaiverFiles, [
        _resolved(tmp.path, 'src/serv/data/verilator_waiver.vlt'),
      ]);
      // `W` has no default → declaration only, nothing applied.
      expect(imported.verilatorExtraOptions, isEmpty);
      expect(imported.defines, isEmpty);
      expect(imported.warnings, isEmpty);
    });

    test('file_type routes languages, and mixing VHDL with Verilog is '
        'mixed', () {
      final edam = writeEdam('''
version: 0.2.1
name: mixed_design
toplevel: top
files:
- {file_type: verilogSource-2005, name: a.v}
- {file_type: systemVerilogSource, name: b.sv}
- {file_type: vhdlSource-2008, name: c.vhd}
''');
      final imported = const EdamReader().read(edam.path);
      expect(imported.language, HdlLanguage.mixed);
      expect(
        imported.sourceFileLanguages[_resolved(tmp.path, 'a.v')],
        ProjectSourceFileLanguage.verilog,
      );
      expect(
        imported.sourceFileLanguages[_resolved(tmp.path, 'b.sv')],
        ProjectSourceFileLanguage.systemVerilog,
      );
      expect(
        imported.sourceFileLanguages[_resolved(tmp.path, 'c.vhd')],
        ProjectSourceFileLanguage.vhdl,
      );
    });

    test('verilog + systemVerilog collapses to systemVerilog', () {
      final edam = writeEdam('''
version: 0.2.1
files:
- {file_type: verilogSource, name: a.v}
- {file_type: systemVerilogSource, name: b.sv}
''');
      expect(
        const EdamReader().read(edam.path).language,
        HdlLanguage.systemVerilog,
      );
    });

    test('is_include_file contributes its directory (or include_path) and '
        'is not a source', () {
      final edam = writeEdam('''
version: 0.2.1
files:
- {file_type: verilogSource, name: rtl/top.v}
- {file_type: verilogSource, name: inc/defs.vh, is_include_file: true}
- {file_type: verilogSource, name: other/hdr.vh, is_include_file: true, include_path: other}
''');
      final imported = const EdamReader().read(edam.path);
      expect(imported.sourceFiles, [_resolved(tmp.path, 'rtl/top.v')]);
      expect(imported.includePaths, [
        _resolved(tmp.path, 'inc'),
        _resolved(tmp.path, 'other'),
      ]);
    });

    test('unsupported file_type warns and skips', () {
      final edam = writeEdam('''
version: 0.2.1
files:
- {file_type: verilogSource, name: top.v}
- {file_type: tclSource, name: constraints.tcl}
''');
      final imported = const EdamReader().read(edam.path);
      expect(imported.sourceFiles, [_resolved(tmp.path, 'top.v')]);
      expect(
        imported.warnings,
        contains(contains('unsupported file_type "tclSource"')),
      );
    });

    test('vlogdefine defaults become defines; bools render 1/0', () {
      final edam = writeEdam('''
version: 0.2.1
files:
- {file_type: verilogSource, name: top.v}
parameters:
  RISCV_FORMAL:
    datatype: bool
    paramtype: vlogdefine
  WITH_CSR:
    datatype: bool
    paramtype: vlogdefine
    default: true
  WIDTH:
    datatype: int
    paramtype: vlogdefine
    default: 8
''');
      final imported = const EdamReader().read(edam.path);
      // Declaration-only parameters must NOT be defined — defining
      // RISCV_FORMAL would change the design under lint.
      expect(imported.defines, {'WITH_CSR': '1', 'WIDTH': '8'});
    });

    test('vlogparam defaults become Verilator -G options with a warning', () {
      final edam = writeEdam('''
version: 0.2.1
files:
- {file_type: verilogSource, name: top.v}
parameters:
  W:
    datatype: int
    paramtype: vlogparam
    default: 4
''');
      final imported = const EdamReader().read(edam.path);
      expect(imported.verilatorExtraOptions, ['-GW=4']);
      expect(imported.warnings, contains(contains('-GW=4')));
    });

    test('plusarg / cmdlinearg defaults warn and are ignored', () {
      final edam = writeEdam('''
version: 0.2.1
files:
- {file_type: verilogSource, name: top.v}
parameters:
  firmware:
    datatype: str
    paramtype: plusarg
    default: fw.hex
''');
      final imported = const EdamReader().read(edam.path);
      expect(imported.defines, isEmpty);
      expect(imported.verilatorExtraOptions, isEmpty);
      expect(imported.warnings, contains(contains('plusarg')));
    });

    test('non-W verilator_options land in extraOptions', () {
      final edam = writeEdam('''
version: 0.2.1
files:
- {file_type: verilogSource, name: top.v}
tool_options:
  verilator:
    verilator_options:
    - -Wall
    - -Wno-DECLFILENAME
    - --timing
''');
      final imported = const EdamReader().read(edam.path);
      expect(imported.verilatorWarnFlags, ['all', 'no-DECLFILENAME']);
      expect(imported.verilatorExtraOptions, ['--timing']);
    });

    test('no verilator_options leaves warnFlags null so the engine default '
        'stays in force', () {
      final edam = writeEdam('''
version: 0.2.1
files:
- {file_type: verilogSource, name: top.v}
''');
      expect(const EdamReader().read(edam.path).verilatorWarnFlags, isNull);
    });

    test('tool_options for other tools warn and are ignored', () {
      final edam = writeEdam('''
version: 0.2.1
files:
- {file_type: verilogSource, name: top.v}
tool_options:
  icarus:
    iverilog_options: [-g2012]
''');
      final imported = const EdamReader().read(edam.path);
      expect(
        imported.warnings,
        contains(contains('tool_options for "icarus"')),
      );
    });

    test('unexpected EDAM version warns but imports', () {
      final edam = writeEdam('''
version: 0.3.0
files:
- {file_type: verilogSource, name: top.v}
''');
      final imported = const EdamReader().read(edam.path);
      expect(imported.sourceFiles, hasLength(1));
      expect(imported.warnings, contains(contains('0.3.0')));
    });

    test('non-empty hooks / filters / vpi warn', () {
      final edam = writeEdam('''
version: 0.2.1
files:
- {file_type: verilogSource, name: top.v}
hooks:
  pre_build:
  - some_hook
vpi:
- {name: my_vpi}
''');
      final imported = const EdamReader().read(edam.path);
      expect(imported.warnings, contains(contains('"hooks"')));
      expect(imported.warnings, contains(contains('"vpi"')));
    });

    test('toplevel as a list takes the first entry and warns when there are '
        'more', () {
      final edam = writeEdam('''
version: 0.2.1
toplevel: [top_a, top_b]
files:
- {file_type: verilogSource, name: top.v}
''');
      final imported = const EdamReader().read(edam.path);
      expect(imported.toplevel, 'top_a');
      expect(imported.warnings, contains(contains('"toplevel"')));
    });

    test('missing file throws EdamImportException', () {
      expect(
        () => const EdamReader().read(p.join(tmp.path, 'nope.eda.yml')),
        throwsA(
          isA<EdamImportException>().having(
            (e) => e.message,
            'message',
            contains('not found'),
          ),
        ),
      );
    });

    test('invalid YAML throws EdamImportException', () {
      final edam = writeEdam('files: [unclosed');
      expect(
        () => const EdamReader().read(edam.path),
        throwsA(isA<EdamImportException>()),
      );
    });

    test('an EDAM with zero lintable sources throws', () {
      final edam = writeEdam('''
version: 0.2.1
files:
- {file_type: tclSource, name: constraints.tcl}
''');
      expect(
        () => const EdamReader().read(edam.path),
        throwsA(
          isA<EdamImportException>().having(
            (e) => e.message,
            'message',
            contains('no lintable HDL sources'),
          ),
        ),
      );
    });

    test('absolute file names are kept as-is (normalized)', () {
      final absSource = p.join(tmp.path, 'elsewhere', 'top.v');
      final edam = writeEdam('''
version: 0.2.1
files:
- {file_type: verilogSource, name: $absSource}
''');
      final imported = const EdamReader().read(edam.path);
      expect(imported.sourceFiles, [p.normalize(absSource)]);
    });
  });
}
