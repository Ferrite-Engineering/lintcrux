// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/services/engines/ghdl/ghdl_parser.dart';

// Real GHDL 6.0.0 diagnostic headers — note the absent space before the
// severity word, which is what GHDL genuinely prints.
const _realHide =
    'demo.vhd:17:14:warning: declaration of "rst" hides port "rst" [-Whide]';
const _realUnused =
    'demo.vhd:13:19:warning: variable "shared_count" is never referenced '
    '[-Wunused]';

void main() {
  // What GHDL actually prints. Verified byte-for-byte against GHDL
  // 6.0.0 (the pinned version) and 5.1.1 (N-1), both macOS arm64 —
  // see `test/fixtures/engines/ghdl/captured/ghdl_6_0_0_analyse/`.
  //
  // Two things differ from the idealized GCC form this parser was
  // originally written against, and both were fatal: there is NO space
  // between the location and the severity word, and the source-context
  // echo carries no `NN |` line-number gutter.
  group('GhdlParser real GHDL 6.0.0 output', () {
    const realTranscript = <String>[
      _realHide,
      '    variable rst : integer;',
      '             ^',
      'demo.vhd:24:11:error: no declaration for "bad_signal"',
      '  dout <= bad_signal;',
      '          ^',
      _realUnused,
      '  shared variable shared_count : integer := 0;',
      '                  ^',
      'ghdl:error: compilation error',
    ];

    test('every diagnostic parses (the unspaced severity regression)', () {
      final parser = GhdlParser(rootPath: '/work/vhdl');
      final notes = <String>[];
      final out = parser.parse(realTranscript, onUnrecognized: notes.add);

      expect(
        out,
        hasLength(3),
        reason:
            'requiring whitespace before the severity word made this '
            'transcript parse to zero violations on stock GHDL',
      );

      expect(out[0].ruleId, 'ghdl/hide');
      expect(out[0].severity, Severity.warning);
      expect(out[0].message, 'declaration of "rst" hides port "rst"');
      expect(out[0].location.file, '/work/vhdl/demo.vhd');
      expect(out[0].location.line, 17);
      expect(out[0].location.column, 14);
      expect(out[0].raw['ghdl.flag'], '-Whide');

      expect(out[1].ruleId, 'ghdl/UNCLASSIFIED');
      expect(out[1].severity, Severity.error);
      expect(out[1].message, 'no declaration for "bad_signal"');
      expect(out[1].location.line, 24);
      expect(out[1].location.column, 11);

      expect(out[2].ruleId, 'ghdl/unused');
      expect(out[2].severity, Severity.warning);
      expect(out[2].location.line, 13);
    });

    test('source echo + caret land in ghdl.continuation, gutter or not', () {
      final parser = GhdlParser(rootPath: '/work/vhdl');
      final out = parser.parse(realTranscript);
      expect(out[0].raw['ghdl.continuation'], <String>[
        '    variable rst : integer;',
        '             ^',
      ]);
    });

    test("GHDL's own failure summary is a notification, not context", () {
      final parser = GhdlParser(rootPath: '/work/vhdl');
      final notes = <String>[];
      final out = parser.parse(realTranscript, onUnrecognized: notes.add);
      expect(notes, contains('ghdl:error: compilation error'));
      // …and it is NOT glued onto the last diagnostic's context, where
      // the inspector would render it as part of an unrelated warning.
      expect(
        out.last.raw['ghdl.continuation'],
        isNot(contains('ghdl:error: compilation error')),
      );
    });

    test('an absolute-path tool message is recognized too', () {
      final parser = GhdlParser(rootPath: '/work/vhdl');
      final notes = <String>[];
      final out = parser.parse(const <String>[
        '/opt/homebrew/bin/ghdl:error: unknown warning identifier: bogus',
      ], onUnrecognized: notes.add);
      expect(out, isEmpty);
      expect(notes, hasLength(1));
    });
  });

  group('GhdlParser', () {
    test('parses a single warning with flag and column', () {
      final parser = GhdlParser(rootPath: '/work/vhdl');
      final out = parser.parse(const [
        'design.vhd:42:13: warning: unused variable "x" [-Wunused]',
      ]);
      expect(out, hasLength(1));
      expect(out.single.engineId, 'ghdl');
      expect(out.single.ruleId, 'ghdl/unused');
      expect(out.single.severity, Severity.warning);
      expect(out.single.message, 'unused variable "x"');
      expect(out.single.location.file, '/work/vhdl/design.vhd');
      expect(out.single.location.line, 42);
      expect(out.single.location.column, 13);
      expect(out.single.raw['ghdl.flag'], '-Wunused');
    });

    test('Windows drive-letter path parses (colon after C:)', () {
      // Regression: the greedy [^:]+ file group stopped at the colon in
      // `C:`, dropping every GHDL diagnostic on Windows.
      final parser = GhdlParser(rootPath: '/work/vhdl');
      final out = parser.parse(const [
        r'C:\proj\top.vhd:12:5: error: type mismatch in port map',
      ]);
      expect(out, hasLength(1));
      expect(out.single.severity, Severity.error);
      expect(out.single.location.file, r'C:\proj\top.vhd');
      expect(out.single.location.line, 12);
      expect(out.single.location.column, 5);
    });

    test('parses an error severity and maps to Severity.error', () {
      final parser = GhdlParser(rootPath: '/x');
      final out = parser.parse(const [
        'a.vhd:1:1: error: type mismatch in port map',
      ]);
      expect(out, hasLength(1));
      expect(out.single.severity, Severity.error);
      expect(out.single.ruleId, 'ghdl/UNCLASSIFIED');
    });

    test('parses note/info/remark severities as Severity.note', () {
      final parser = GhdlParser(rootPath: '/x');
      final out = parser.parse(const [
        'a.vhd:1:1: note: alpha',
        'a.vhd:2:1: info: beta',
        'a.vhd:3:1: remark: gamma',
      ]);
      expect(out.map((v) => v.severity).toSet(), {Severity.note});
    });

    test('absorbs continuation lines into ghdl.continuation', () {
      final parser = GhdlParser(rootPath: '/x');
      final out = parser.parse(const [
        'b.vhd:7:5: warning: hidden declaration [-Whide]',
        '   7 |   variable hidden : integer;',
        '     |            ^',
      ]);
      expect(out, hasLength(1));
      final cont = out.single.raw['ghdl.continuation'];
      expect(cont, isA<List<String>>());
      expect((cont as List).length, 2);
    });

    test('rule id strips -W prefix from flag', () {
      final parser = GhdlParser(rootPath: '/x');
      final out = parser.parse(const [
        'a.vhd:1:1: warning: msg [-Wbinding]',
        'a.vhd:1:2: warning: msg2 [reserved]',
      ]);
      expect(out, hasLength(2));
      expect(out[0].ruleId, 'ghdl/binding');
      expect(out[1].ruleId, 'ghdl/reserved');
    });

    test('handles optional column (older GHDL builds)', () {
      final parser = GhdlParser(rootPath: '/x');
      final out = parser.parse(const [
        'old.vhd:99: warning: ancient style',
      ]);
      expect(out, hasLength(1));
      expect(out.single.location.line, 99);
      expect(out.single.location.column, 1);
    });

    test('resolves relative paths against rootPath', () {
      final parser = GhdlParser(rootPath: '/work/vhdl');
      final out = parser.parse(const [
        'sub/component.vhd:5:1: warning: msg',
      ]);
      expect(out.single.location.file, '/work/vhdl/sub/component.vhd');
    });

    test('passes absolute paths through unchanged', () {
      final parser = GhdlParser(rootPath: '/work/vhdl');
      final out = parser.parse(const [
        '/absolute/x.vhd:1:1: warning: msg',
      ]);
      expect(out.single.location.file, '/absolute/x.vhd');
    });

    test('silently ignores banner / non-header lines outside a diagnostic', () {
      final parser = GhdlParser(rootPath: '/x');
      final out = parser.parse(const [
        'GHDL 4.1.0 (Ubuntu)',
        '',
        'a.vhd:1:1: warning: msg',
      ]);
      expect(out, hasLength(1));
    });

    test('handles multiple diagnostics back to back', () {
      final parser = GhdlParser(rootPath: '/x');
      final out = parser.parse(const [
        'a.vhd:1:1: warning: msg1 [-Wbinding]',
        'a.vhd:2:1: warning: msg2 [-Wreserved]',
        'a.vhd:3:1: error: bigger problem',
      ]);
      expect(out, hasLength(3));
      expect(out[0].ruleId, 'ghdl/binding');
      expect(out[1].ruleId, 'ghdl/reserved');
      expect(out[2].severity, Severity.error);
    });
  });
}
