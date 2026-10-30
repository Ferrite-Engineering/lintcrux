// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/rohd/rohd_inline_trace.dart';

List<String> _lines(String text) => const LineSplitter().convert(text);

String _at(RohdInlineFrame f) => '${f.file}:${f.line}:${f.column}';

void main() {
  group('parseRohdInlineTraces — real ROHD output', () {
    final traces = parseRohdInlineTraces(
      _lines(File('verification/fixtures/rohd/top.sv').readAsStringSync()),
    );
    RohdInlineTrace on(int line) => traces.firstWhere((t) => t.line == line);

    test('finds the commented lines and no others', () {
      expect(traces.map((t) => t.line), containsAll(<int>[43, 48, 50, 61]));
      // A read inside always_comb carries no comment.
      expect(traces.any((t) => t.line == 53), isFalse);
      // A port declaration carries none either.
      expect(traces.any((t) => t.line == 35), isFalse);
    });

    test('a comment is a stack of frames, innermost first', () {
      expect(on(61).frames.map(_at), [
        'lib/design.dart:21:29',
        'lib/design.dart:58:19',
      ]);
    });

    test('`| frame` rejoins the previous stack at that frame', () {
      // Line 45: `0:9:9 | 0:51:19`, after line 44's `0:8:9 0:51:19`.
      expect(on(45).frames.map(_at), [
        'lib/design.dart:9:9',
        'lib/design.dart:51:19',
      ]);
    });

    test('a bare `^` repeats the previous stack', () {
      expect(on(63).frames.map(_at), on(62).frames.map(_at));
    });
  });

  group('parseRohdInlineTraces — the encodings', () {
    test('`^N` takes the first N frames of the previous stack', () {
      final traces = parseRohdInlineTraces(
        _lines('''
// Source files:
//   0: lib/a.dart
logic a; // ROHD: 0:1:1 0:2:2 0:3:3
logic b; // ROHD: ^2 0:9:9
'''),
      );
      expect(traces[1].frames.map(_at), [
        'lib/a.dart:1:1',
        'lib/a.dart:2:2',
        'lib/a.dart:9:9',
      ]);
    });

    test('a prefix and a rejoin combine', () {
      final traces = parseRohdInlineTraces(
        _lines('''
// Source files:
//   0: lib/a.dart
logic a; // ROHD: 0:1:1 0:2:2 0:3:3
logic b; // ROHD: ^1 0:7:7 | 0:3:3
'''),
      );
      expect(traces[1].frames.map(_at), [
        'lib/a.dart:1:1',
        'lib/a.dart:7:7',
        'lib/a.dart:3:3',
      ]);
    });

    test('each module has its own file table', () {
      final traces = parseRohdInlineTraces(
        _lines('''
// Source files:
//   0: lib/a.dart
logic a; // ROHD: 0:1:1
endmodule
// Source files:
//   0: lib/b.dart
logic b; // ROHD: 0:5:5
'''),
      );
      expect(traces.map((t) => t.frames.single.file), [
        'lib/a.dart',
        'lib/b.dart',
      ]);
    });
  });

  group('parseRohdInlineTraces — malformed input is skipped', () {
    test('a `^` with nothing before it, a bad index, bad numbers', () {
      final traces = parseRohdInlineTraces(
        _lines('''
// Source files:
//   0: lib/a.dart
logic a; // ROHD: ^
logic b; // ROHD: ^5 0:1:1
logic c; // ROHD: 4:1:1
logic d; // ROHD: x:y:z
logic e; // ROHD: 0:1:1 |
logic f; // ROHD:
logic g; // ROHD: 0:2:2
'''),
      );
      expect(traces.map((t) => t.line), [9]);
    });

    test('empty and comment-free text gives nothing', () {
      expect(parseRohdInlineTraces(const <String>[]), isEmpty);
      expect(parseRohdInlineTraces(['module m;', 'endmodule']), isEmpty);
    });
  });
}
