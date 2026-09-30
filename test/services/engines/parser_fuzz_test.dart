// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/ghdl/ghdl_parser.dart';
import 'package:lintcrux/services/engines/slang/slang_parser.dart';
import 'package:lintcrux/services/engines/svlint/svlint_parser.dart';
import 'package:lintcrux/services/engines/verible/verible_parser.dart';
import 'package:lintcrux/services/engines/verilator/verilator_parser.dart';

/// Adversarial fuzz sweep over every hand-rolled engine parser.
///
/// Proves the **log-and-continue contract** holds under hostile input:
/// no parser ever throws, every parser always returns a `List<Violation>`
/// (possibly empty), valid lines mixed with garbage are still parsed, and
/// every unrecognized line is *surfaced* via the `onUnrecognized` sink
/// (which the engine layer lowers to SARIF `toolExecutionNotifications`)
/// rather than dropped on the floor. Fixed-seed so failures reproduce.
class _FuzzTarget {
  const _FuzzTarget({
    required this.id,
    required this.parse,
    required this.validLine,
    required this.ansiValidLine,
    this.isJson = false,
  });

  /// Engine id (for test labels).
  final String id;

  /// The parser entry point under test.
  final List<Violation> Function(
    List<String> lines, {
    void Function(String line)? onUnrecognized,
  })
  parse;

  /// A line the parser is known to recognize as exactly one violation.
  final String validLine;

  /// A valid diagnostic whose *message* carries residual ANSI escapes —
  /// the parser must still parse it (NO_COLOR defense in depth).
  final String ansiValidLine;

  /// Whether this engine consumes JSON-line output (enables the
  /// truncated-JSON case).
  final bool isJson;
}

const String _esc = '\x1B';

List<_FuzzTarget> _targets() {
  const root = '/work';
  // The 6-character JSON escape sequence for ESC (backslash-u-0-0-1-b),
  // built from the backslash code point so the source can't be mangled
  // into a raw control byte. json.decode turns this into a real ESC.
  final jsonEsc = '${String.fromCharCode(0x5C)}u001b';
  return <_FuzzTarget>[
    _FuzzTarget(
      id: 'verilator',
      parse: (lines, {onUnrecognized}) => VerilatorParser(
        rootPath: root,
      ).parse(lines, onUnrecognized: onUnrecognized),
      validLine: "%Warning-UNUSEDSIGNAL: top.sv:42:13: Signal is not used: 'x'",
      ansiValidLine:
          '%Warning-UNUSEDSIGNAL: top.sv:42:13: '
          "$_esc[31mSignal is not used$_esc[0m: 'x'",
    ),
    _FuzzTarget(
      id: 'ghdl',
      parse: (lines, {onUnrecognized}) => GhdlParser(
        rootPath: root,
      ).parse(lines, onUnrecognized: onUnrecognized),
      validLine: 'design.vhd:42:13: warning: unused variable "x" [-Wunused]',
      ansiValidLine:
          'design.vhd:42:13: warning: '
          '$_esc[31munused variable$_esc[0m "x" [-Wunused]',
    ),
    _FuzzTarget(
      id: 'verible',
      isJson: true,
      parse: (lines, {onUnrecognized}) => VeribleParser(
        rootPath: root,
      ).parseJsonLines(lines, onUnrecognized: onUnrecognized),
      validLine:
          '{"path":"a.sv","line":3,"column":5,"rule":"no-tabs",'
          '"severity":"warning","message":"Use spaces"}',
      // JSON engines never emit raw control bytes — residual ANSI arrives
      // as a JSON unicode escape that decodes to an ESC inside the message.
      // message. The parser must still produce the violation.
      ansiValidLine:
          '{"path":"a.sv","line":3,"column":5,"rule":"no-tabs",'
          '"severity":"warning","message":"$jsonEsc[31mUse spaces$jsonEsc[0m"}',
    ),
    _FuzzTarget(
      id: 'slang',
      isJson: true,
      parse: (lines, {onUnrecognized}) => SlangParser(
        rootPath: root,
      ).parseJsonLines(lines, onUnrecognized: onUnrecognized),
      validLine:
          '{"severity":"warning","code":"slang::diag::ImplicitConvert",'
          '"message":"conv","location":{"file":"a.sv","line":3,"column":5}}',
      ansiValidLine:
          '{"severity":"warning","code":"slang::diag::ImplicitConvert",'
          '"message":"$jsonEsc[31mconv$jsonEsc[0m",'
          '"location":{"file":"a.sv","line":3,"column":5}}',
    ),
    _FuzzTarget(
      id: 'svlint',
      isJson: true,
      parse: (lines, {onUnrecognized}) => SvlintParser(
        rootPath: root,
      ).parseJsonLines(lines, onUnrecognized: onUnrecognized),
      validLine:
          '{"path":"a.sv","line":3,"column":5,"rule":"no_tab",'
          '"message":"no tabs"}',
      ansiValidLine:
          '{"path":"a.sv","line":3,"column":5,"rule":"no_tab",'
          '"message":"$jsonEsc[31mno tabs$jsonEsc[0m"}',
    ),
  ];
}

/// A line that no parser recognizes (no JSON, no `file:line:col`).
const String _garbage = '~~~ not a diagnostic at all ~~~';

String _randomBytesLine(Random rng, int maxLen) {
  final len = rng.nextInt(maxLen);
  return String.fromCharCodes(
    List<int>.generate(len, (_) => rng.nextInt(256)),
  );
}

void main() {
  for (final t in _targets()) {
    group('parser fuzz: ${t.id}', () {
      // Baseline: the "valid" line really is recognized, so the
      // interleaving / preservation assertions below are meaningful.
      test('valid line parses to exactly one violation', () {
        expect(t.parse(<String>[t.validLine]), hasLength(1));
      });

      test('empty input → empty list, no throw', () {
        final notes = <String>[];
        final out = t.parse(<String>[], onUnrecognized: notes.add);
        expect(out, isEmpty);
        expect(notes, isEmpty);
      });

      test('single garbage line → not fatal, surfaced as a notification', () {
        final notes = <String>[];
        final out = t.parse(<String>[_garbage], onUnrecognized: notes.add);
        expect(out, isA<List<Violation>>());
        expect(
          notes,
          contains(_garbage),
          reason: 'unrecognized line must be surfaced, not dropped',
        );
      });

      test('valid + garbage interleaved → valid kept, garbage surfaced', () {
        final notes = <String>[];
        final out = t.parse(
          <String>[_garbage, t.validLine],
          onUnrecognized: notes.add,
        );
        expect(
          out,
          isNotEmpty,
          reason: 'the valid line must survive alongside garbage',
        );
        expect(notes, contains(_garbage));
      });

      test('ANSI-wrapped message still parses (NO_COLOR defense in depth)', () {
        expect(t.parse(<String>[t.ansiValidLine]), isNotEmpty);
      });

      test('lines with embedded CR / CRLF / lone LF → no throw', () {
        final input = <String>[
          'a\rb',
          'c\r\nd',
          'e\nf',
          t.validLine,
        ];
        expect(() => t.parse(input), returnsNormally);
      });

      test('NUL bytes in the stream → no throw', () {
        final input = <String>[
          'valid\x00line',
          '\x00\x00\x00',
          t.validLine,
        ];
        expect(t.parse(input), isA<List<Violation>>());
      });

      test('invalid-UTF-16 / multibyte in paths and messages → no throw', () {
        final input = <String>[
          // Lone surrogate (invalid on its own) + CJK multibyte.
          'path_${String.fromCharCode(0xD800)}日本語.sv:1:1: garbage',
          t.validLine,
        ];
        expect(() => t.parse(input), returnsNormally);
      });

      test('10K-line random byte stream → no throw, returns a list', () {
        final rng = Random(0x1117CC);
        final input = List<String>.generate(
          10000,
          (_) => _randomBytesLine(rng, 64),
        );
        expect(t.parse(input), isA<List<Violation>>());
      });

      test(
        'pathologically long line (>1 MB) → bounded, no quadratic blowup',
        () {
          final huge = 'x' * (1024 * 1024 + 7);
          expect(() => t.parse(<String>[huge, t.validLine]), returnsNormally);
        },
        timeout: const Timeout(Duration(seconds: 5)),
      );

      if (t.isJson) {
        test('truncated mid-token JSON → skipped, not fatal', () {
          final input = <String>[
            '{"path":"a.sv","line":3,"column":',
            '{"severity":"warning","code":',
            t.validLine,
          ];
          expect(() => t.parse(input), returnsNormally);
        });
      }
    });
  }
}
