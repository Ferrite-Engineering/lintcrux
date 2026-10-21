// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/constraint_format.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/services/engines/cdc/cdc_source_span.dart';
import 'package:lintcrux/services/engines/constraints/constraint_checks.dart';
import 'package:lintcrux/services/engines/constraints/constraint_parsers.dart';
import 'package:lintcrux/services/engines/yosys/yosys_elaboration.dart';

// The six checks over hand-built ports and hand-written constraint text.

const _clk = ElaboratedPort(name: 'clk', direction: 'input', width: 1);
const _btn = ElaboratedPort(name: 'btn', direction: 'input', width: 1);
// [3:0]
const _led = ElaboratedPort(name: 'led', direction: 'output', width: 4);

ParsedConstraintFile _file(
  String text, {
  String path = '/p/pins.pcf',
  ConstraintFormat format = ConstraintFormat.pcf,
}) => ParsedConstraintFile(
  path: path,
  format: format,
  result: parseConstraintText(format, text),
);

List<ConstraintFinding> _check(
  List<ElaboratedPort> ports,
  List<ParsedConstraintFile> files,
) => checkConstraints(ports: ports, files: files, topModule: 'top');

List<String> _rules(List<ConstraintFinding> findings) => [
  for (final f in findings) '${f.ruleId}@${f.line}',
];

const _allPlaced =
    'set_io clk 1\nset_io btn 2\n'
    'set_io led[0] 3\nset_io led[1] 4\nset_io led[2] 5\nset_io led[3] 6\n';

void main() {
  test('a complete, consistent file has no finding', () {
    expect(_check([_clk, _btn, _led], [_file(_allPlaced)]), isEmpty);
  });

  group('constraints/unknown-port', () {
    test('a name top does not have is an error on its line and column', () {
      final f = _check(
        [_clk, _btn, _led],
        [
          _file('${_allPlaced}set_io  rst 9\n'),
        ],
      ).single;
      expect(f.ruleId, ConstraintRuleIds.unknownPort);
      expect(f.severity, Severity.error);
      expect(f.line, 7);
      expect(f.column, 9);
      expect(f.message, contains('`rst`'));
      expect(f.message, isNot(contains('Did you mean')));
    });

    test('one close name is suggested, case-insensitively', () {
      final f = _check(
        [_clk, _btn, _led],
        [
          _file('${_allPlaced}set_io CLL 9\n'),
        ],
      ).single;
      expect(f.message, contains('Did you mean `clk`?'));
    });

    test('two equally close names suggest nothing', () {
      const a = ElaboratedPort(name: 'bta', direction: 'input', width: 1);
      const b = ElaboratedPort(name: 'btb', direction: 'input', width: 1);
      final findings = _check(
        [a, b],
        [
          _file('set_io bt 1\nset_io bta 2\nset_io btb 3\n'),
        ],
      );
      expect(findings.single.message, isNot(contains('Did you mean')));
    });

    test('a name more than two edits away suggests nothing', () {
      final f = _check(
        [_clk, _btn, _led],
        [
          _file('${_allPlaced}set_io button 9\n'),
        ],
      ).single;
      expect(f.message, isNot(contains('Did you mean')));
    });

    test('a bus named without a bit is unknown, and says so', () {
      final f = _check(
        [_clk, _btn, _led],
        [
          _file('set_io clk 1\nset_io btn 2\nset_io led 3\n'),
        ],
      );
      final unknown = f.where((x) => x.ruleId == ConstraintRuleIds.unknownPort);
      expect(unknown.single.message, contains('4-bit bus'));
      expect(unknown.single.message, contains('led[3]'));
    });

    test('a name that only mentions a port (IOBUF) is still checked', () {
      final f = _check(
        [_clk],
        [
          _file(
            'LOCATE COMP "clk" SITE "A1";\nIOBUF PORT "clx" IO_TYPE=LVCMOS33;',
            path: '/p/pins.lpf',
            format: ConstraintFormat.lpf,
          ),
        ],
      );
      expect(_rules(f), ['unknown-port@2']);
    });
  });

  group('constraints/bit-out-of-range', () {
    ElaboratedPort bus({int offset = 0, bool upto = false, int width = 8}) =>
        ElaboratedPort(
          name: 'd',
          direction: 'output',
          width: width,
          offset: offset,
          upto: upto,
        );

    List<String> inRange(ElaboratedPort port, List<int> bits) {
      final text = [for (final b in bits) 'set_io d[$b] ${100 + b}'].join('\n');
      return [
        for (final f in _check([port], [_file(text)]))
          if (f.ruleId == ConstraintRuleIds.bitOutOfRange)
            f.message.split('`')[1],
      ];
    }

    test('[7:0]: 7 and 0 exist, 8 and -1 do not', () {
      expect(inRange(bus(), [0, 7]), isEmpty);
      expect(inRange(bus(), [8]), ['d[8]']);
    });

    test('[0:7] resolves the same indexes as [7:0]', () {
      expect(inRange(bus(upto: true), [0, 7]), isEmpty);
      expect(inRange(bus(upto: true), [8]), ['d[8]']);
    });

    test('[8:1]: 1 to 8 exist, 0 and 9 do not', () {
      expect(inRange(bus(offset: 1), [1, 8]), isEmpty);
      expect(inRange(bus(offset: 1), [0, 9]), ['d[0]', 'd[9]']);
    });

    test('the message states the declared range as the RTL wrote it', () {
      String say(ElaboratedPort port) => _check(
        [port],
        [_file('set_io d[20] 1')],
      ).firstWhere((f) => f.ruleId == ConstraintRuleIds.bitOutOfRange).message;
      expect(say(bus()), contains('[7:0]'));
      expect(say(bus(upto: true)), contains('[0:7]'));
      expect(say(bus(offset: 1)), contains('[8:1]'));
    });

    test('a scalar accepts [0], as nextpnr does, and rejects other bits', () {
      final ok = _check([_clk], [_file('set_io clk[0] 1')]);
      expect(ok, isEmpty);
      final bad = _check(
        [_clk],
        [
          _file('set_io clk[1] 1'),
        ],
      ).singleWhere((f) => f.ruleId == ConstraintRuleIds.bitOutOfRange);
      expect(bad.message, contains('single bit'));
    });
  });

  group('constraints/unconstrained-port', () {
    test('a port with no line is a warning on its declaration', () {
      const span = ElaboratedPort(
        name: 'btn',
        direction: 'input',
        width: 1,
        declaration: CdcSourceSpan(file: '/p/top.v', line: 5, column: 18),
      );
      final f = _check(
        [_clk, span, _led],
        [
          _file(
            'set_io clk 1\nset_io led[0] 3\nset_io led[1] 4\n'
            'set_io led[2] 5\nset_io led[3] 6\n',
          ),
        ],
      ).single;
      expect(f.ruleId, ConstraintRuleIds.unconstrainedPort);
      expect(f.severity, Severity.warning);
      expect(f.declaration?.file, '/p/top.v');
      expect(f.declaration?.line, 5);
      expect(f.message, contains('`btn`'));
    });

    test('a bus lists the bits that have no pin, once per port', () {
      final findings = _check(
        [_led],
        [
          _file('set_io led[3] 1\nset_io led[0] 2\n'),
        ],
      );
      final f = findings.single;
      expect(f.ruleId, ConstraintRuleIds.unconstrainedPort);
      expect(f.message, contains('2, 1'));
      expect(f.message, contains('`led`'));
    });

    test('a bus with no bit placed names the port and its width', () {
      final f = _check([_led], [_file('# nothing\n')]).single;
      expect(f.message, contains('(4 bits)'));
    });

    test('a long list is cut and counted', () {
      const wide = ElaboratedPort(name: 'w', direction: 'input', width: 40);
      final f = _check([wide], [_file('set_io w[0] 1')]).single;
      expect(f.message, contains('and 23 more'));
    });

    test('with no declaration it sits on the first constraint file', () {
      final f = _check([_clk], [_file('# empty')]).single;
      expect(f.declaration, isNull);
      expect(f.file, '/p/pins.pcf');
      expect(f.line, 1);
    });

    test('lines that only name a port (IOBUF) do not place it', () {
      final f = _check(
        [_clk],
        [
          _file(
            'IOBUF PORT "clk" IO_TYPE=LVCMOS33;',
            path: '/p/pins.lpf',
            format: ConstraintFormat.lpf,
          ),
        ],
      );
      expect(f.map((x) => x.ruleId), [ConstraintRuleIds.unconstrainedPort]);
    });

    test('each format is judged on its own files', () {
      final findings = _check(
        [_clk],
        [
          _file('set_io clk 1'),
          _file(
            'IO_PORT "clk" IO_TYPE=LVCMOS33;',
            path: '/p/pins.cst',
            format: ConstraintFormat.cst,
          ),
        ],
      );
      expect(findings, hasLength(1));
      expect(findings.single.file, '/p/pins.cst');
    });
  });

  group('constraints/pin-reused', () {
    test('every later port on the same pin is an error, the first is not', () {
      final f = _check(
        [_clk, _btn, _led],
        [
          _file(
            'set_io clk 1\nset_io btn 1\nset_io led[0] 1\nset_io led[1] 4\n'
            'set_io led[2] 5\nset_io led[3] 6\n',
          ),
        ],
      );
      expect(_rules(f), ['pin-reused@2', 'pin-reused@3']);
      expect(f.first.message, contains('`clk`'));
      expect(f.first.message, contains('line 1 of pins.pcf'));
    });

    test('the same port twice on the same pin is not a reuse', () {
      final f = _check([_clk], [_file('set_io clk 1\nset_io clk 1\n')]);
      expect(f, isEmpty);
    });

    test('pins of different formats are different pins', () {
      final f = _check(
        [_clk],
        [
          _file('set_io clk 1'),
          _file(
            'IO_LOC "clk" 1;',
            path: '/p/pins.cst',
            format: ConstraintFormat.cst,
          ),
        ],
      );
      expect(f, isEmpty);
    });
  });

  group('constraints/port-reassigned', () {
    test('the same bit on two pins is a warning on the later line', () {
      final f = _check([_clk], [_file('set_io clk 1\nset_io clk 2\n')]).single;
      expect(f.ruleId, ConstraintRuleIds.portReassigned);
      expect(f.severity, Severity.warning);
      expect(f.line, 2);
      expect(f.message, contains('`1`'));
      expect(f.message, contains('`2`'));
    });

    test('different bits of a bus on different pins are not reassigned', () {
      final f = _check(
        [_led],
        [
          _file(
            'set_io led[0] 1\nset_io led[1] 2\nset_io led[2] 3\n'
            'set_io led[3] 4\n',
          ),
        ],
      );
      expect(f, isEmpty);
    });

    test('across two files of one format the later line is reported', () {
      final f = _check(
        [_clk],
        [
          _file('set_io clk 1', path: '/p/a.pcf'),
          _file('set_io clk 2', path: '/p/b.pcf'),
        ],
      ).single;
      expect(f.file, '/p/b.pcf');
      expect(f.message, contains('a.pcf'));
    });
  });

  group('constraints/unparsed-line', () {
    test('an unrecognised line is a note on its line, never dropped', () {
      final f = _check(
        [_clk],
        [_file('set_io clk 1\nfrobnicate clk\n')],
      ).single;
      expect(f.ruleId, ConstraintRuleIds.unparsedLine);
      expect(f.severity, Severity.note);
      expect(f.line, 2);
      expect(f.message, contains('frobnicate clk'));
    });
  });
}
