// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/services/engines/verible/verible_parser.dart';

const _jsonLine =
    '{"path":"top.sv","line":42,"column":13,"severity":"warning","rule":"no-tabs","message":"Use spaces instead of tabs"}';
const _jsonLineExtra =
    '{"path":"top.sv","line":1,"column":1,"severity":"warning","rule":"r","message":"m","extraField":"keep"}';
const _jsonLineNoRule =
    '{"path":"top.sv","line":1,"column":1,"severity":"warning","message":"m"}';
const _jsonLineAbs =
    '{"path":"/abs/top.sv","line":1,"column":1,"severity":"warning","rule":"r","message":"m"}';
const _jsonLineMinimal =
    '{"path":"top.sv","line":1,"column":1,"severity":"warning","rule":"r","message":"m"}';

void main() {
  group('VeribleParser JSON-line mode', () {
    final parser = VeribleParser(rootPath: '/work/soc');

    test('parses a fully-formed jsonline violation', () {
      final out = parser.parseJsonLines(<String>[_jsonLine]);
      expect(out, hasLength(1));
      final v = out.single;
      expect(v.engineId, 'verible');
      expect(v.ruleId, 'verible/no-tabs');
      expect(v.severity, Severity.warning);
      expect(v.message, 'Use spaces instead of tabs');
      expect(v.location.file, '/work/soc/top.sv');
      expect(v.location.line, 42);
      expect(v.location.column, 13);
    });

    test('preserves the full json object in raw for forward-compat', () {
      final out = parser.parseJsonLines(<String>[_jsonLineExtra]);
      expect(out.single.raw['extraField'], 'keep');
    });

    test('falls back to UNCLASSIFIED when rule is absent', () {
      final out = parser.parseJsonLines(<String>[_jsonLineNoRule]);
      expect(out.single.ruleId, 'verible/UNCLASSIFIED');
    });

    test('maps every supported severity', () {
      const cases = {
        'error': Severity.error,
        'warning': Severity.warning,
        'info': Severity.note,
        'note': Severity.note,
      };
      for (final entry in cases.entries) {
        final line =
            '{"path":"a.sv","line":1,"column":1,"severity":"${entry.key}","rule":"r","message":"m"}';
        expect(
          parser.parseJsonLines(<String>[line]).single.severity,
          entry.value,
        );
      }
    });

    test('absolute paths are passed through unchanged', () {
      final out = parser.parseJsonLines(<String>[_jsonLineAbs]);
      expect(out.single.location.file, '/abs/top.sv');
    });

    test('non-JSON lines fall through to the text parser', () {
      final out = parser.parseJsonLines(
        <String>['top.sv:42:13: warning: tabs not allowed [no-tabs]'],
      );
      expect(out, hasLength(1));
      expect(out.single.ruleId, 'verible/no-tabs');
    });

    test('malformed JSON is skipped silently', () {
      final out = parser.parseJsonLines(<String>[
        '{"path":"top.sv", malformed',
        _jsonLineMinimal,
      ]);
      expect(out, hasLength(1));
    });

    test('JSON missing required fields is skipped', () {
      final out = parser.parseJsonLines(<String>[
        '{"path":"top.sv"}',
        '{"line":1,"column":1,"message":"m"}',
      ]);
      expect(out, isEmpty);
    });

    test('empty input produces no violations', () {
      expect(parser.parseJsonLines(const []), isEmpty);
    });

    test('blank lines are ignored', () {
      final out = parser.parseJsonLines(<String>[
        '',
        '   ',
        _jsonLineMinimal,
      ]);
      expect(out, hasLength(1));
    });
  });

  group('VeribleParser text mode', () {
    final parser = VeribleParser(rootPath: '/work/soc');

    test('parses a typical text-mode line', () {
      final out = parser.parseText(
        <String>['top.sv:42:13: warning: tabs not allowed [no-tabs]'],
      );
      expect(out, hasLength(1));
      final v = out.single;
      expect(v.ruleId, 'verible/no-tabs');
      expect(v.severity, Severity.warning);
      expect(v.location.file, '/work/soc/top.sv');
      expect(v.location.line, 42);
      expect(v.location.column, 13);
      expect(v.message, 'tabs not allowed');
    });

    test('text without severity prefix defaults to warning', () {
      final out = parser.parseText(<String>[
        'top.sv:42:13: bad style [no-tabs]',
      ]);
      expect(out.single.severity, Severity.warning);
    });

    test('text without rule defaults to UNCLASSIFIED', () {
      final out = parser.parseText(<String>[
        'top.sv:42:13: warning: bad style',
      ]);
      expect(out.single.ruleId, 'verible/UNCLASSIFIED');
    });

    test('absolute paths pass through unchanged', () {
      final out = parser.parseText(<String>[
        '/abs/top.sv:1:1: warning: msg [rule]',
      ]);
      expect(out.single.location.file, '/abs/top.sv');
    });

    // Beta regression: every upstream `verible-verilog-lint`
    // release emits a column RANGE, and the anchored `line:col:` pattern
    // rejected all of them. The log-and-continue contract then dropped
    // 2,365 findings without a word and the run reported "Completed".
    test('parses upstream column-range syntax file:LINE:COL-COL2:', () {
      final out = parser.parseText(<String>[
        'top.sv:8:24-42: Line length exceeds max: 100; is: 118 [line-length]',
      ]);
      expect(out, hasLength(1));
      final v = out.single;
      expect(v.location.file, '/work/soc/top.sv');
      expect(v.location.line, 8);
      // COL stays the anchor column; the range end is not modeled.
      expect(v.location.column, 24);
      expect(v.ruleId, 'verible/line-length');
      expect(v.message, 'Line length exceeds max: 100; is: 118');
    });

    test('parses the double-bracket [Style: …] [rule] form', () {
      final out = parser.parseText(<String>[
        'rtl/cpu.sv:12:1-8: Use spaces, not tabs. [Style: tabs] [no-tabs]',
      ]);
      expect(out, hasLength(1));
      final v = out.single;
      expect(v.ruleId, 'verible/no-tabs');
      // The style-category tag is metadata, not part of the diagnostic.
      expect(v.message, 'Use spaces, not tabs.');
      expect(v.location.line, 12);
      expect(v.location.column, 1);
    });

    test('a column range with a severity prefix still parses', () {
      final out = parser.parseText(<String>[
        'top.sv:3:5-9: error: syntax error [parse]',
      ]);
      expect(out.single.severity, Severity.error);
      expect(out.single.location.column, 5);
    });

    test('lines that do not match the pattern are skipped', () {
      final out = parser.parseText(<String>[
        'this is not a violation',
        'top.sv:42:13: warning: msg [rule]',
        'also not a violation',
      ]);
      expect(out, hasLength(1));
    });
  });

  // Verible's text-mode file group is `.+?`, so the filename a design
  // file plants with a `line directive arrives whole — and JSON mode
  // hands over `path` verbatim. Both must be contained before the string
  // can reach the editor argv on a click.
  group('VeribleParser hostile filenames', () {
    final parser = VeribleParser(rootPath: '/work/soc');

    test('text mode contains a +command filename under the root', () {
      final out = parser.parseText(const [
        '+:!curl x|sh:42:13: warning: planted [rule]',
      ]);
      expect(out, hasLength(1));
      expect(out.single.location.file, '/work/soc/+:!curl x|sh');
    });

    test('text mode refuses an escaping path and reports it', () {
      final unrecognized = <String>[];
      final out = parser.parseText(
        const ['../../../etc/shadow:1:1: warning: planted [rule]'],
        onUnrecognized: unrecognized.add,
      );
      expect(out, isEmpty);
      expect(unrecognized, hasLength(1));
    });

    test('JSON mode refuses an escaping path and reports it', () {
      const planted =
          '{"path":"../../../etc/shadow","line":1,"column":1,'
          '"severity":"warning","rule":"r","message":"planted"}';
      final unrecognized = <String>[];
      final out = parser.parseJsonLines(
        const <String>[planted],
        onUnrecognized: unrecognized.add,
      );
      expect(out, isEmpty);
      expect(unrecognized, hasLength(1));
    });
  });
}
