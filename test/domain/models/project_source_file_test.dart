// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/models/project_source_file.dart';

void main() {
  group('ProjectSourceFile', () {
    test('default language is auto', () {
      const f = ProjectSourceFile(path: 'a.sv');
      expect(f.language, ProjectSourceFileLanguage.auto);
    });

    test('equality compares path and language', () {
      const a = ProjectSourceFile(path: 'x.v');
      const b = ProjectSourceFile(path: 'x.v');
      const c = ProjectSourceFile(
        path: 'x.v',
        language: ProjectSourceFileLanguage.verilog,
      );
      expect(a, equals(b));
      expect(a == c, isFalse);
    });

    test('copyWith preserves untouched fields', () {
      const a = ProjectSourceFile(
        path: 'x.v',
        language: ProjectSourceFileLanguage.verilog,
      );
      final n = a.copyWith(path: 'y.v');
      expect(n.path, 'y.v');
      expect(n.language, ProjectSourceFileLanguage.verilog);
    });

    group('resolveLanguage', () {
      test('honors explicit language declarations', () {
        const a = ProjectSourceFile(
          path: 'x.v',
          language: ProjectSourceFileLanguage.systemVerilog,
        );
        expect(a.resolveLanguage(), HdlLanguage.systemVerilog);
      });

      test('extension detection: .v → verilog', () {
        const a = ProjectSourceFile(path: 'src/x.v');
        expect(a.resolveLanguage(), HdlLanguage.verilog);
      });

      test('extension detection: .sv → systemVerilog', () {
        const a = ProjectSourceFile(path: 'src/x.sv');
        expect(a.resolveLanguage(), HdlLanguage.systemVerilog);
      });

      test('extension detection: .vhd → vhdl', () {
        const a = ProjectSourceFile(path: 'src/x.vhd');
        expect(a.resolveLanguage(), HdlLanguage.vhdl);
      });

      test('extension detection: .vhdl → vhdl', () {
        const a = ProjectSourceFile(path: 'src/x.vhdl');
        expect(a.resolveLanguage(), HdlLanguage.vhdl);
      });

      test('extension detection is case-insensitive', () {
        const a = ProjectSourceFile(path: 'src/X.VHD');
        expect(a.resolveLanguage(), HdlLanguage.vhdl);
      });

      test('unknown extensions default to systemVerilog', () {
        const a = ProjectSourceFile(path: 'src/x.unknown');
        expect(a.resolveLanguage(), HdlLanguage.systemVerilog);
      });

      test('extension detection: .svh → systemVerilog header', () {
        const a = ProjectSourceFile(path: 'src/x.svh');
        expect(a.resolveLanguage(), HdlLanguage.systemVerilog);
      });

      test('extension detection: .vh → verilog header', () {
        const a = ProjectSourceFile(path: 'src/x.vh');
        expect(a.resolveLanguage(), HdlLanguage.verilog);
      });
    });
  });
}
