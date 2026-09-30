// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/services/engines/slang/slang_parser.dart';

const _jsonLine =
    '{"severity":"warning","code":"slang::diag::ImplicitConvert","message":"Implicit conversion","location":{"file":"top.sv","line":42,"column":13}}';
const _jsonLineFatal =
    '{"severity":"fatal","code":"BadFatal","message":"oops","location":{"file":"top.sv","line":1,"column":1}}';
const _jsonLineWshort =
    '{"severity":"warning","code":"-Wshort","message":"too short","location":{"file":"top.sv","line":2,"column":3}}';
const _jsonLineNoCode =
    '{"severity":"warning","message":"hmm","location":{"file":"top.sv","line":2,"column":3}}';
// Real slang 11.0.0 text-mode header lines, copied from
// `test/fixtures/engines/slang/captured/slang_11_0_0_text/output.txt`.
const _realTextError =
    "top.sv:15:23: error: use of undeclared identifier 'undeclared_thing'";
const _realTextWarning =
    "top.sv:8:15: warning: unused variable 'never_used' [-Wunused-variable]";
// A `--diag-json` element whose location is a Windows path: the
// drive-letter colon must survive the right-to-left split.
const _realJsonWindows =
    '[{"severity":"warning","message":"m","optionName":"width-trunc",'
    r'"location":"C:\\rtl\\top.sv:8:15"}]';
const _jsonLineAbs =
    '{"severity":"warning","code":"X","message":"m","location":{"file":"/abs/top.sv","line":1,"column":1}}';

void main() {
  group('SlangParser JSON mode', () {
    final parser = SlangParser(rootPath: '/work/soc');

    test('parses a fully-formed slang diagnostic', () {
      final out = parser.parseJsonLines(<String>[_jsonLine]);
      expect(out, hasLength(1));
      final v = out.single;
      expect(v.engineId, 'slang');
      expect(v.ruleId, 'slang/ImplicitConvert');
      expect(v.severity, Severity.warning);
      expect(v.message, 'Implicit conversion');
      expect(v.location.file, '/work/soc/top.sv');
      expect(v.location.line, 42);
      expect(v.location.column, 13);
    });

    test('fatal maps to error severity', () {
      final out = parser.parseJsonLines(<String>[_jsonLineFatal]);
      expect(out.single.severity, Severity.error);
    });

    test('strips the -W prefix from code', () {
      final out = parser.parseJsonLines(<String>[_jsonLineWshort]);
      expect(out.single.ruleId, 'slang/short');
    });

    test('uses UNCLASSIFIED when code is absent', () {
      final out = parser.parseJsonLines(<String>[_jsonLineNoCode]);
      expect(out.single.ruleId, 'slang/UNCLASSIFIED');
    });

    test('absolute paths pass through unchanged', () {
      final out = parser.parseJsonLines(<String>[_jsonLineAbs]);
      expect(out.single.location.file, '/abs/top.sv');
    });

    test('preserves the full JSON object in raw for forward-compat', () {
      final out = parser.parseJsonLines(<String>[_jsonLine]);
      expect(out.single.raw['code'], 'slang::diag::ImplicitConvert');
    });

    test('malformed JSON is skipped silently', () {
      final out = parser.parseJsonLines(<String>[
        '{"bogus',
        _jsonLine,
      ]);
      expect(out, hasLength(1));
    });

    test('JSON missing required fields is skipped', () {
      final out = parser.parseJsonLines(<String>[
        '{"severity":"warning","message":"m"}',
        '{"severity":"warning","message":"m","location":{}}',
      ]);
      expect(out, isEmpty);
    });

    test('blank lines are ignored', () {
      final out = parser.parseJsonLines(<String>[
        '',
        '   ',
        _jsonLine,
      ]);
      expect(out, hasLength(1));
    });

    test('non-JSON lines fall through to the text parser', () {
      final out = parser.parseJsonLines(
        <String>['top.sv:42:13: warning: tabs not allowed [no-tabs]'],
      );
      expect(out, hasLength(1));
      expect(out.single.ruleId, 'slang/no-tabs');
    });
  });

  // The shape slang 11.0.0 actually emits for `--diag-json -`: ONE
  // pretty-printed array, `location` as a "file:line:column" string,
  // rule id in `optionName`. Copied from a real run — see
  // `test/fixtures/engines/slang/captured/slang_11_0_0_diag_json/`.
  group('SlangParser --diag-json (real slang 11.0.0 shape)', () {
    final parser = SlangParser(rootPath: '/work/soc');
    const realArray = <String>[
      '[',
      '  {',
      '    "severity": "error",',
      '    "message": "use of undeclared identifier \'undeclared_thing\'",',
      '    "location": "top.sv:15:23",',
      '    "symbolPath": "top"',
      '  },',
      '  {',
      '    "severity": "warning",',
      '    "message": "unused variable \'never_used\'",',
      '    "optionName": "unused-variable",',
      '    "location": "top.sv:8:15",',
      '    "symbolPath": "top.never_used"',
      '  }',
      ']',
    ];

    test('a multi-line JSON array yields every diagnostic', () {
      final out = parser.parseJsonLines(realArray);
      expect(out, hasLength(2));

      expect(out[0].severity, Severity.error);
      // Errors carry no `optionName`.
      expect(out[0].ruleId, 'slang/UNCLASSIFIED');
      expect(out[0].message, "use of undeclared identifier 'undeclared_thing'");
      expect(out[0].location.file, '/work/soc/top.sv');
      expect(out[0].location.line, 15);
      expect(out[0].location.column, 23);

      expect(out[1].severity, Severity.warning);
      expect(out[1].ruleId, 'slang/unused-variable');
      expect(out[1].message, "unused variable 'never_used'");
      expect(out[1].location.file, '/work/soc/top.sv');
      expect(out[1].location.line, 8);
      expect(out[1].location.column, 15);
    });

    test('slang banner around the array surfaces as notifications', () {
      final notes = <String>[];
      final out = parser.parseJsonLines(<String>[
        'Top level design units:',
        '    top',
        '',
        ...realArray,
        'Build failed: 1 error, 1 warning',
      ], onUnrecognized: notes.add);
      expect(out, hasLength(2));
      expect(notes, contains('Top level design units:'));
      expect(notes, contains('Build failed: 1 error, 1 warning'));
    });

    test('JSON and text modes agree on rule ids', () {
      final fromJson = parser.parseJsonLines(realArray);
      final fromText = parser.parseText(<String>[
        _realTextError,
        '  assign narrow_out = undeclared_thing;',
        '                      ^~~~~~~~~~~~~~~~',
        _realTextWarning,
        '  logic       never_used;',
        '              ^',
      ]);
      expect(
        fromText.map((v) => v.ruleId).toList(),
        fromJson.map((v) => v.ruleId).toList(),
      );
      expect(
        fromText.map((v) => v.severity).toList(),
        fromJson.map((v) => v.severity).toList(),
      );
    });

    test('a Windows location string keeps its drive-letter colon', () {
      final out = parser.parseJsonLines(<String>[_realJsonWindows]);
      expect(out.single.location.file, r'C:\rtl\top.sv');
      expect(out.single.location.line, 8);
      expect(out.single.location.column, 15);
    });

    test('a truncated array is skipped, not fatal', () {
      final notes = <String>[];
      final out = parser.parseJsonLines(<String>[
        '[',
        '  {',
        '    "severity": "warning",',
      ], onUnrecognized: notes.add);
      expect(out, isEmpty);
      expect(notes, isNotEmpty);
    });
  });

  group('SlangParser text mode', () {
    final parser = SlangParser(rootPath: '/work/soc');

    test('parses a typical text-mode line', () {
      final out = parser.parseText(
        <String>['top.sv:42:13: warning: bad style [no-tabs]'],
      );
      expect(out, hasLength(1));
      final v = out.single;
      expect(v.ruleId, 'slang/no-tabs');
      expect(v.severity, Severity.warning);
      expect(v.location.file, '/work/soc/top.sv');
      expect(v.location.line, 42);
      expect(v.location.column, 13);
      expect(v.message, 'bad style');
    });

    test('captures source-context lines under raw["slang.context"]', () {
      final out = parser.parseText(<String>[
        'top.sv:42:13: warning: bad style [no-tabs]',
        '   42 |  reg foo;',
        '      |       ^',
      ]);
      final ctx = out.single.raw['slang.context'] as List<dynamic>;
      expect(ctx.length, 2);
    });

    test('text without rule defaults to UNCLASSIFIED', () {
      final out = parser.parseText(
        <String>['top.sv:42:13: warning: bad style'],
      );
      expect(out.single.ruleId, 'slang/UNCLASSIFIED');
    });

    test('absolute paths pass through unchanged', () {
      final out = parser.parseText(
        <String>['/abs/top.sv:1:1: warning: msg [rule]'],
      );
      expect(out.single.location.file, '/abs/top.sv');
    });

    test('lines that do not match the pattern are skipped', () {
      final out = parser.parseText(<String>[
        'this is not a violation',
        'top.sv:42:13: warning: msg [rule]',
      ]);
      expect(out, hasLength(1));
    });

    test('fatal severity maps to error', () {
      final out = parser.parseText(
        <String>['top.sv:1:1: fatal: very bad [x]'],
      );
      expect(out.single.severity, Severity.error);
    });

    test('multiple consecutive violations are decoded individually', () {
      final out = parser.parseText(<String>[
        'a.sv:1:1: warning: m1 [r1]',
        'a.sv:2:1: error: m2 [r2]',
      ]);
      expect(out, hasLength(2));
      expect(out[0].severity, Severity.warning);
      expect(out[1].severity, Severity.error);
    });
  });
}
