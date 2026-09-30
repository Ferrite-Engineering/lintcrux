// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/lint_project.dart';

void main() {
  group('LintProject', () {
    test('required fields produce a usable project with sensible defaults', () {
      const p = LintProject(name: 'top', rootPath: '/tmp/proj');
      expect(p.sourceFiles, isEmpty);
      expect(p.includePaths, isEmpty);
      expect(p.defines, isEmpty);
      expect(p.topModule, isNull);
      expect(p.language, HdlLanguage.systemVerilog);
      expect(p.enabledEngineIds, isEmpty);
      expect(p.severityOverrides, isEmpty);
      expect(p.perEngineOptions, isEmpty);
      expect(p.sourceFileProvenance, isEmpty);
    });

    test('sourceFileProvenance participates in copyWith and equality', () {
      const p = LintProject(name: 'top', rootPath: '/r');
      final withProvenance = p.copyWith(
        sourceFiles: const ['/r/a.v'],
        sourceFileProvenance: const {'/r/a.v': 'vendor:lib:core:1.0'},
      );
      expect(
        withProvenance.sourceFileProvenance['/r/a.v'],
        'vendor:lib:core:1.0',
      );
      // Unrelated copyWith calls must not disturb it.
      expect(
        withProvenance.copyWith(topModule: 'top').sourceFileProvenance,
        withProvenance.sourceFileProvenance,
      );
      const a = LintProject(
        name: 'top',
        rootPath: '/r',
        sourceFileProvenance: {'/r/a.v': 'vendor:lib:core:1.0'},
      );
      const b = LintProject(
        name: 'top',
        rootPath: '/r',
        sourceFileProvenance: {'/r/a.v': 'vendor:lib:core:1.0'},
      );
      const c = LintProject(
        name: 'top',
        rootPath: '/r',
        sourceFileProvenance: {'/r/a.v': 'vendor:lib:other:2.0'},
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('copyWith updates fields without disturbing others', () {
      const p = LintProject(name: 'top', rootPath: '/tmp/proj');
      final next = p.copyWith(
        sourceFiles: const ['/tmp/proj/a.v', '/tmp/proj/b.v'],
        defines: const {'WIDTH': '8'},
        topModule: 'top',
        enabledEngineIds: const ['verilator'],
        severityOverrides: const {
          'verilator/UNUSEDSIGNAL': Severity.error,
        },
        perEngineOptions: const {
          'verilator': {'extraArgs': '-Wall'},
        },
      );
      expect(next.name, 'top');
      expect(next.sourceFiles, ['/tmp/proj/a.v', '/tmp/proj/b.v']);
      expect(next.defines, {'WIDTH': '8'});
      expect(next.topModule, 'top');
      expect(next.enabledEngineIds, ['verilator']);
      expect(next.severityOverrides['verilator/UNUSEDSIGNAL'], Severity.error);
      expect(next.perEngineOptions['verilator']?['extraArgs'], '-Wall');
    });

    test(
      '== treats nested perEngineOptions maps with equal contents as equal',
      () {
        const a = LintProject(
          name: 'top',
          rootPath: '/r',
          perEngineOptions: {
            'verilator': {'extraArgs': '-Wall'},
            'verible': {'rules': 'no-tabs'},
          },
        );
        const b = LintProject(
          name: 'top',
          rootPath: '/r',
          perEngineOptions: {
            'verilator': {'extraArgs': '-Wall'},
            'verible': {'rules': 'no-tabs'},
          },
        );
        expect(a, b);
        expect(a.hashCode, b.hashCode);
      },
    );

    test('== distinguishes differing perEngineOptions values', () {
      const a = LintProject(
        name: 'top',
        rootPath: '/r',
        perEngineOptions: {
          'verilator': {'extraArgs': '-Wall'},
        },
      );
      const b = LintProject(
        name: 'top',
        rootPath: '/r',
        perEngineOptions: {
          'verilator': {'extraArgs': '-Wextra'},
        },
      );
      expect(a, isNot(b));
    });

    test('== compares list/map contents', () {
      const a = LintProject(
        name: 'top',
        rootPath: '/r',
        sourceFiles: ['/r/a.v'],
        defines: {'W': '8'},
        enabledEngineIds: ['verilator'],
        severityOverrides: {'verilator/X': Severity.error},
      );
      const b = LintProject(
        name: 'top',
        rootPath: '/r',
        sourceFiles: ['/r/a.v'],
        defines: {'W': '8'},
        enabledEngineIds: ['verilator'],
        severityOverrides: {'verilator/X': Severity.error},
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('== distinguishes differing source-file order', () {
      const a = LintProject(
        name: 'top',
        rootPath: '/r',
        sourceFiles: ['/r/a.v', '/r/b.v'],
      );
      const b = LintProject(
        name: 'top',
        rootPath: '/r',
        sourceFiles: ['/r/b.v', '/r/a.v'],
      );
      expect(a, isNot(b));
    });
  });
}
