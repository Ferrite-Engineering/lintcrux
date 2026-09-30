// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/services/engines/svlint/svlint_parser.dart';

void main() {
  group('SvlintParser', () {
    test('parses a JSON violation', () {
      final parser = SvlintParser(rootPath: '/work/sv');
      const jsonLine =
          '{"path":"top.sv","line":42,"column":13,"rule":"non_blocking_assignment_in_always_comb","message":"non-blocking assignment in always_comb","severity":"warning"}';
      final out = parser.parseJsonLines(const [jsonLine]);
      expect(out, hasLength(1));
      expect(out.single.engineId, 'svlint');
      expect(
        out.single.ruleId,
        'svlint/non_blocking_assignment_in_always_comb',
      );
      expect(out.single.severity, Severity.warning);
      expect(out.single.message, 'non-blocking assignment in always_comb');
      expect(out.single.location.file, '/work/sv/top.sv');
      expect(out.single.location.line, 42);
      expect(out.single.location.column, 13);
    });

    test('falls back to hint when message is absent', () {
      final parser = SvlintParser(rootPath: '/x');
      const jsonLine =
          '{"path":"a.sv","line":1,"column":1,"rule":"foo","hint":"hint text"}';
      final out = parser.parseJsonLines(const [jsonLine]);
      expect(out.single.message, 'hint text');
    });

    test('json mode falls back to text parsing for non-JSON lines', () {
      final parser = SvlintParser(rootPath: '/x');
      const j1 =
          '{"path":"a.sv","line":1,"column":1,"rule":"r1","message":"m1"}';
      const t2 = 'b.sv:2:3: Warning: m2 [r2]';
      final out = parser.parseJsonLines(const [j1, t2]);
      expect(out, hasLength(2));
      expect(out[0].ruleId, 'svlint/r1');
      expect(out[1].ruleId, 'svlint/r2');
    });

    test('text mode parses GCC-style header', () {
      final parser = SvlintParser(rootPath: '/work/sv');
      final out = parser.parseText(const [
        'top.sv:5:9: Warning: avoid wildcard imports [wildcard_import]',
      ]);
      expect(out, hasLength(1));
      expect(out.single.ruleId, 'svlint/wildcard_import');
      expect(out.single.location.line, 5);
      expect(out.single.location.column, 9);
    });

    test('error severity maps to Severity.error', () {
      final parser = SvlintParser(rootPath: '/x');
      final out = parser.parseText(const [
        'a.sv:1:1: Error: thing [r]',
      ]);
      expect(out.single.severity, Severity.error);
    });

    test('info / hint / note map to Severity.note', () {
      final parser = SvlintParser(rootPath: '/x');
      final out = parser.parseText(const [
        'a.sv:1:1: Info: a [r]',
        'a.sv:2:1: Hint: b [r]',
        'a.sv:3:1: Note: c [r]',
      ]);
      expect(out.map((v) => v.severity).toSet(), {Severity.note});
    });

    test('absolute paths are passed through unchanged', () {
      final parser = SvlintParser(rootPath: '/work/sv');
      const jsonLine =
          '{"path":"/absolute/x.sv","line":1,"column":1,"rule":"r","message":"m"}';
      final out = parser.parseJsonLines(const [jsonLine]);
      expect(out.single.location.file, '/absolute/x.sv');
    });

    test('absorbs continuation lines in text mode under svlint.context', () {
      final parser = SvlintParser(rootPath: '/x');
      final out = parser.parseText(const [
        'a.sv:1:1: Warning: msg [r]',
        '   hint: maybe use foo()',
        '   ^',
      ]);
      expect(out, hasLength(1));
      expect(out.single.raw['svlint.context'], isA<List<String>>());
    });

    test('json with missing required fields is dropped silently', () {
      final parser = SvlintParser(rootPath: '/x');
      // missing line
      const jsonLine = '{"path":"a.sv","column":1,"rule":"r","message":"m"}';
      final out = parser.parseJsonLines(const [jsonLine]);
      expect(out, isEmpty);
    });
  });
}
