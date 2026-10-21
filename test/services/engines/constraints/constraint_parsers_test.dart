// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/constraint_format.dart';
import 'package:lintcrux/services/engines/constraints/constraint_model.dart';
import 'package:lintcrux/services/engines/constraints/constraint_parsers.dart';

// The three readers accept what nextpnr's own readers accept. Each case below
// is a line form read off the reader's source (ice40/pcf.cc, ecp5/lpf.cc,
// himbaechel/uarch/gowin/cst.cc), written out by hand.

ConstraintParseResult _pcf(String text) =>
    parseConstraintText(ConstraintFormat.pcf, text);
ConstraintParseResult _lpf(String text) =>
    parseConstraintText(ConstraintFormat.lpf, text);
ConstraintParseResult _cst(String text) =>
    parseConstraintText(ConstraintFormat.cst, text);

String _show(ConstraintEntry e) =>
    '${e.written}>${e.pin}@${e.line}:${e.column}';

void main() {
  group('format by extension', () {
    test('three extensions, any case, nothing else', () {
      expect(ConstraintFormat.fromPath('a/b/pins.pcf'), ConstraintFormat.pcf);
      expect(ConstraintFormat.fromPath('PINS.LPF'), ConstraintFormat.lpf);
      expect(ConstraintFormat.fromPath('board.cst'), ConstraintFormat.cst);
      expect(ConstraintFormat.fromPath('board.sdc'), isNull);
      expect(ConstraintFormat.fromPath('pcf'), isNull);
    });

    test('EDAM file types are compared exactly, as Edalize does', () {
      expect(ConstraintFormat.fromEdamFileType('PCF'), ConstraintFormat.pcf);
      expect(ConstraintFormat.fromEdamFileType('LPF'), ConstraintFormat.lpf);
      expect(ConstraintFormat.fromEdamFileType('CST'), ConstraintFormat.cst);
      expect(ConstraintFormat.fromEdamFileType('pcf'), isNull);
      expect(ConstraintFormat.fromEdamFileType('SDC'), isNull);
    });
  });

  group('PCF', () {
    test('set_io places a port, with its bit and column', () {
      final r = _pcf('set_io clk 35\nset_io  led[3]   27\n');
      expect(r.entries.map(_show), ['clk>35@1:8', 'led[3]>27@2:9']);
      expect(r.unparsed, isEmpty);
    });

    test(
      'flags: -pullup and -pullup_resistor take a value, -nowarn does not',
      () {
        final r = _pcf(
          'set_io -pullup yes a 1\n'
          'set_io -nowarn b 2\n'
          'set_io -pullup_resistor 10K -nowarn c 3\n'
          'set_io --warn-no-port d 4\n'
          'set_io -unheard e 5\n',
        );
        expect(
          r.entries.map((e) => '${e.written}>${e.pin}'),
          ['a>1', 'b>2', 'c>3', 'd>4', 'e>5'],
        );
        expect(r.unparsed, isEmpty);
      },
    );

    test('comments start at # anywhere; blank lines are skipped', () {
      final r = _pcf('# whole line\n\nset_io a 1 # trailing\n   # indented\n');
      expect(r.entries.map(_show), ['a>1@3:8']);
      expect(r.unparsed, isEmpty);
    });

    test('set_frequency is read and names no port', () {
      final r = _pcf('set_frequency clk 12\n');
      expect(r.entries, isEmpty);
      expect(r.unparsed, isEmpty);
    });

    test('a set_io without a port and a pin, and any other command, are '
        'reported', () {
      final r = _pcf('set_io a\nset_io\nset_frequency clk\nfoo bar\n');
      expect(r.unparsed.map((u) => u.line), [1, 2, 3, 4]);
      expect(r.unparsed.last.text, 'foo bar');
      expect(r.entries, isEmpty);
    });

    test('an escaped bracket is not unescaped', () {
      final r = _pcf(r'set_io led\[3\] 27');
      expect(r.entries.single.port, r'led\[3\]');
      expect(r.entries.single.bit, isNull);
    });
  });

  group('LPF', () {
    test('LOCATE COMP names a port and a site, quotes removed', () {
      final r = _lpf(
        'LOCATE COMP "clk" SITE "R4";\nLOCATE COMP "led[1]" SITE "B2";',
      );
      expect(r.entries.map(_show), ['clk>R4@1:14', 'led[1]>B2@2:14']);
      expect(r.unparsed, isEmpty);
    });

    test('IOBUF PORT names a port and places nothing', () {
      final r = _lpf('IOBUF PORT "clk" IO_TYPE=LVCMOS33 PULLMODE=UP;');
      expect(r.entries.single.port, 'clk');
      expect(r.entries.single.pin, isNull);
    });

    test('a statement runs to its semicolon and may span lines', () {
      final r = _lpf(
        'LOCATE\n  COMP "a"\n  SITE "A1"\n;\nLOCATE COMP "b" SITE "B1";',
      );
      expect(r.entries.map((e) => '${e.written}>${e.pin}@${e.line}'), [
        'a>A1@2',
        'b>B1@5',
      ]);
    });

    test('two statements on one line', () {
      final r = _lpf('LOCATE COMP "a" SITE "A1"; LOCATE COMP "b" SITE "B1";');
      expect(r.entries.map((e) => e.written), ['a', 'b']);
    });

    test('comments start at # or //', () {
      final r = _lpf('# x\n// y\nLOCATE COMP "a" SITE "A1"; // z\n');
      expect(r.entries.map((e) => e.written), ['a']);
      expect(r.unparsed, isEmpty);
    });

    test('BLOCK, SYSCONFIG and FREQUENCY are read and name no port', () {
      final r = _lpf(
        'BLOCK RESETPATHS;\n'
        'SYSCONFIG CONFIG_IOVOLTAGE=3.3 MCCLK_FREQ=2.4;\n'
        'FREQUENCY PORT "clk" 25 MHZ;\n',
      );
      expect(r.entries, isEmpty);
      expect(r.unparsed, isEmpty);
    });

    test(
      'unknown verbs, malformed LOCATE and a missing semicolon are reported',
      () {
        final r = _lpf(
          'FOO BAR;\n'
          'LOCATE COMP "a" SITE;\n'
          'LOCATE PORT "a" SITE "A1";\n'
          'LOCATE COMP "a" SITE "A1" EXTRA;\n'
          'LOCATE COMP "a" SITE "A1"',
        );
        expect(r.entries, isEmpty);
        expect(r.unparsed.map((u) => u.line), [1, 2, 3, 4, 5]);
      },
    );

    test('an unterminated quote is reported, not read', () {
      final r = _lpf('LOCATE COMP "a SITE "A1";');
      expect(r.entries, isEmpty);
      expect(r.unparsed, hasLength(1));
    });
  });

  group('CST', () {
    test(
      'IO_LOC names a port and a pin; the pin may be a number or a name',
      () {
        final r = _cst('IO_LOC "clk" 52;\nIO_LOC "led[0]" IOT4A;\n');
        expect(r.entries.map(_show), ['clk>52@1:9', 'led[0]>IOT4A@2:9']);
        expect(r.unparsed, isEmpty);
      },
    );

    test('a differential pair reads the first pin only', () {
      final r = _cst('IO_LOC "d_p" 10, 11;');
      expect(r.entries.single.pin, '10');
    });

    test('IO_PORT names a port and places nothing', () {
      final r = _cst('IO_PORT "clk" IO_TYPE=LVCMOS33 PULL_MODE=UP;');
      expect(r.entries.single.port, 'clk');
      expect(r.entries.single.pin, isNull);
    });

    test('INS_LOC, CLOCK_LOC and USE_ADC_SRC are read and name no port', () {
      final r = _cst(
        'INS_LOC "u" R5C3[0][A];\n'
        'INS_LOC "d" TOPSIDE[0];\n'
        'CLOCK_LOC "n" BUFG[2];\n'
        'USE_ADC_SRC bus1 IOT10;\n',
      );
      expect(r.entries, isEmpty);
      expect(r.unparsed, isEmpty);
    });

    test('a // line is a comment; anything else unknown is reported', () {
      final r = _cst('// note\nBOGUS "x" 1;\n  IO_LOC "a" 1;\nIO_LOC "a";\n');
      expect(r.entries, isEmpty);
      expect(r.unparsed.map((u) => u.line), [2, 3, 4]);
    });

    test('trailing text after the semicolon and a CRLF ending are fine', () {
      final r = _cst('IO_LOC "a" 1; // note\r\nIO_LOC "b" 2;\r\n');
      expect(r.entries.map((e) => e.written), ['a', 'b']);
    });
  });

  test('a line past the bound is reported and skipped', () {
    final long = 'set_io a ${'1' * (kMaxConstraintLineLength + 1)}';
    final r = _pcf('$long\nset_io b 2\n');
    expect(r.entries.map((e) => e.written), ['b']);
    expect(r.unparsed.single.line, 1);
  });

  test('the stream form reads the same as the string form', () async {
    const text = 'set_io a 1\nbogus\nset_io b[2] 3\n';
    final fromStream = await parseConstraintLines(
      ConstraintFormat.pcf,
      Stream<String>.fromIterable(text.split('\n')),
    );
    final fromText = _pcf(text);
    expect(fromStream.entries.map(_show), fromText.entries.map(_show));
    expect(
      fromStream.unparsed.map((u) => u.line),
      fromText.unparsed.map((u) => u.line),
    );
  });
}
