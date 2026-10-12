// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/services/engines/svlint/svlint_parser.dart';

/// One finding as svlint 0.9.5 prints it with no output flag.
const List<String> _failBlock = <String>[
  'Fail: blocking_assignment_in_always_ff',
  '   --> top.sv:10:3',
  '   |',
  '10 |   always_ff @(posedge clk) begin',
  '   |   ^^^^^^^^^ hint  : Do not use blocking assignments within `always_ff`.',
  '   |             reason: Blocking assignment in `always_ff` may cause undefined event ordering.',
  '',
];

const List<String> _parseErrorBlock = <String>[
  'Error: parse error',
  '   --> broken.sv:5:10',
  '  |',
  '5 |     q <= ;',
  '  |          ^',
];

void main() {
  group('SvlintParser', () {
    test('parses a rule failure block into one warning', () {
      final parser = SvlintParser(rootPath: '/work/sv');
      final out = parser.parse(_failBlock);
      expect(out, hasLength(1));
      final v = out.single;
      expect(v.engineId, 'svlint');
      expect(v.ruleId, 'svlint/blocking_assignment_in_always_ff');
      expect(v.severity, Severity.warning);
      expect(
        v.message,
        'Do not use blocking assignments within `always_ff`.',
      );
      expect(v.location.file, '/work/sv/top.sv');
      expect(v.location.line, 10);
      expect(v.location.column, 3);
      expect(
        v.raw['svlint.reason'],
        'Blocking assignment in `always_ff` may cause undefined event '
        'ordering.',
      );
      expect(v.raw['svlint.context'], <String>[
        '   always_ff @(posedge clk) begin',
      ]);
    });

    test('a parse error with a position is an error-level violation', () {
      final parser = SvlintParser(rootPath: '/work/sv');
      final out = parser.parse(_parseErrorBlock);
      expect(out, hasLength(1));
      expect(out.single.ruleId, 'svlint/parse_error');
      expect(out.single.severity, Severity.error);
      expect(out.single.message, 'parse error');
      expect(out.single.location.file, '/work/sv/broken.sv');
      expect(out.single.location.line, 5);
      expect(out.single.location.column, 10);
    });

    test('blocks that follow each other without a blank line both parse', () {
      // svlint prints no separator between an Error block and the first
      // Fail block that follows it.
      final parser = SvlintParser(rootPath: '/work/sv');
      final out = parser.parse(<String>[..._parseErrorBlock, ..._failBlock]);
      expect(out.map((v) => v.ruleId), <String>[
        'svlint/parse_error',
        'svlint/blocking_assignment_in_always_ff',
      ]);
    });

    test('an Error with no position is a notification, not a finding', () {
      final parser = SvlintParser(rootPath: '/work/sv');
      final notes = <String>[];
      final out = parser.parse(
        const <String>['Error: No such file or directory (os error 2)'],
        onUnrecognized: notes.add,
      );
      expect(out, isEmpty);
      expect(notes, <String>['Error: No such file or directory (os error 2)']);
    });

    test('the missing-config warning is surfaced, not parsed', () {
      final parser = SvlintParser(rootPath: '/work/sv');
      final notes = <String>[];
      final out = parser.parse(
        <String>[
          "Warning: Config file '.svlint.toml' is not found. Enable all rules",
          ..._failBlock,
        ],
        onUnrecognized: notes.add,
      );
      expect(out, hasLength(1));
      expect(notes, hasLength(1));
      expect(notes.single, startsWith('Warning: Config file'));
    });

    test('a block with no hint still produces a finding', () {
      final parser = SvlintParser(rootPath: '/x');
      final out = parser.parse(const <String>[
        'Fail: some_rule',
        '   --> a.sv:1:1',
      ]);
      expect(out.single.message, 'svlint rule "some_rule" failed');
      expect(out.single.raw, isNot(contains('svlint.reason')));
    });

    test('absolute paths are passed through unchanged', () {
      final parser = SvlintParser(rootPath: '/work/sv');
      final out = parser.parse(const <String>[
        'Fail: r',
        '   --> /absolute/x.sv:1:1',
      ]);
      expect(out.single.location.file, '/absolute/x.sv');
    });

    test('a path with spaces resolves against the root', () {
      final parser = SvlintParser(rootPath: '/work');
      final out = parser.parse(const <String>[
        'Fail: tab_character',
        '   --> a dir/x.sv:3:1',
        '  |',
        '3 | \tlogic q;',
        '  | ^ hint  : Replace tab with spaces.',
      ]);
      expect(out.single.location.file, '/work/a dir/x.sv');
      expect(out.single.message, 'Replace tab with spaces.');
    });

    test('a block whose path escapes the root is refused as a whole', () {
      final parser = SvlintParser(rootPath: '/work/sv');
      final notes = <String>[];
      final out = parser.parse(
        const <String>[
          'Fail: r',
          '   --> ../../etc/passwd:1:1',
          '  |',
          '1 | root:x:0:0',
          '  | ^ hint  : nope',
        ],
        onUnrecognized: notes.add,
      );
      expect(out, isEmpty);
      // The header is surfaced once; the gutter lines are consumed with it.
      expect(notes, <String>['Fail: r']);
    });

    test('CRLF line endings are tolerated', () {
      final parser = SvlintParser(rootPath: '/x');
      final out = parser.parse(<String>[
        for (final l in _failBlock) '$l\r',
      ]);
      expect(out, hasLength(1));
      expect(out.single.location.line, 10);
    });

    test('lines outside any block are surfaced verbatim', () {
      final parser = SvlintParser(rootPath: '/x');
      final notes = <String>[];
      final out = parser.parse(
        <String>['~~~ stray ~~~', ..._failBlock, 'trailing noise'],
        onUnrecognized: notes.add,
      );
      expect(out, hasLength(1));
      expect(notes, <String>['~~~ stray ~~~', 'trailing noise']);
    });

    test('errorRuleFor slugs the header into an identifier', () {
      expect(SvlintParser.errorRuleFor('parse error'), 'parse_error');
      expect(SvlintParser.errorRuleFor('  Include  error! '), 'include_error');
      expect(SvlintParser.errorRuleFor('***'), 'error');
    });
  });
}
