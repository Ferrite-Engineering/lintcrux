// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:lintcrux/domain/enums/constraint_format.dart';
import 'package:lintcrux/services/engines/constraints/constraint_model.dart';

// Pure Dart: no Flutter, no dart:io. The headless binary imports this.
//
// Each reader accepts what nextpnr's own reader accepts, at the revision
// recorded in each case's PROVENANCE.md under
// verification/fixtures/engines/constraints/captured/:
//
// - PCF: ice40/pcf.cc `apply_pcf`
// - LPF: ecp5/lpf.cc `Arch::apply_lpf`
// - CST: himbaechel/uarch/gowin/cst.cc `GowinCstReader::run`
//
// A line none of them reads is reported in
// [ConstraintParseResult.unparsed], never dropped.

/// The longest line the readers look at. nextpnr reads a line of any length;
/// a constraint line that is not megabytes long is the only kind worth
/// parsing, and a bound keeps one hostile file from becoming one huge string.
const int kMaxConstraintLineLength = 65536;

/// Reads a constraint file of [format] from its [lines], one at a time.
///
/// Takes a stream so a caller reading a file never holds the whole file as
/// one string.
Future<ConstraintParseResult> parseConstraintLines(
  ConstraintFormat format,
  Stream<String> lines,
) async {
  final reader = _readerFor(format);
  var number = 0;
  await for (final line in lines) {
    number++;
    if (line.length > kMaxConstraintLineLength) {
      reader.tooLong(number);
      continue;
    }
    reader.line(line, number);
  }
  return reader.finish();
}

/// Reads [text] as a constraint file of [format].
///
/// For callers that already hold a short string (tests, messages). A file
/// goes through [parseConstraintLines].
ConstraintParseResult parseConstraintText(
  ConstraintFormat format,
  String text,
) {
  final reader = _readerFor(format);
  var number = 0;
  for (final line in const LineSplitter().convert(text)) {
    number++;
    if (line.length > kMaxConstraintLineLength) {
      reader.tooLong(number);
      continue;
    }
    reader.line(line, number);
  }
  return reader.finish();
}

_Reader _readerFor(ConstraintFormat format) => switch (format) {
  ConstraintFormat.pcf => _PcfReader(),
  ConstraintFormat.lpf => _LpfReader(),
  ConstraintFormat.cst => _CstReader(),
};

/// A whitespace-delimited word and where it starts (1-based line and column).
typedef _Word = ({String text, int column, int line});

abstract class _Reader {
  final List<ConstraintEntry> entries = <ConstraintEntry>[];
  final List<UnparsedConstraintLine> unparsed = <UnparsedConstraintLine>[];

  void line(String raw, int number);

  void tooLong(int number) {
    unparsed.add(
      UnparsedConstraintLine(
        line: number,
        column: 1,
        text: 'line longer than $kMaxConstraintLineLength characters',
      ),
    );
  }

  ConstraintParseResult finish() => ConstraintParseResult(
    entries: List<ConstraintEntry>.unmodifiable(entries),
    unparsed: List<UnparsedConstraintLine>.unmodifiable(unparsed),
  );

  void addUnparsed(int line, int column, String text) {
    final trimmed = text.trim();
    unparsed.add(
      UnparsedConstraintLine(
        line: line,
        column: column,
        text: trimmed.length > 80 ? '${trimmed.substring(0, 77)}...' : trimmed,
      ),
    );
  }

  /// Adds an entry for [word] naming a port, optionally placed on [pin].
  void addEntry(_Word word, String? pin) {
    final (port, bit) = _splitBit(word.text);
    entries.add(
      ConstraintEntry(
        port: port,
        bit: bit,
        pin: pin,
        line: word.line,
        column: word.column,
      ),
    );
  }
}

/// `led[3]` gives (`led`, 3); anything else is a name with no index.
///
/// nextpnr names the cell of a port bit `led[3]`, so the brackets are part of
/// the name it looks up. Nothing is unescaped: a backslash stays in the name.
(String, int?) _splitBit(String name) {
  final match = _bitPattern.firstMatch(name);
  if (match == null) return (name, null);
  final bit = int.tryParse(match.group(2)!);
  if (bit == null) return (name, null);
  return (match.group(1)!, bit);
}

final RegExp _bitPattern = RegExp(r'^(.+)\[(\d+)\]$');

/// Splits [text] on whitespace the way `std::stringstream >>` does.
List<_Word> _words(String text, int line) {
  final out = <_Word>[];
  var start = -1;
  for (var i = 0; i <= text.length; i++) {
    final space = i == text.length || _isSpace(text.codeUnitAt(i));
    if (space) {
      if (start >= 0) {
        out.add((
          text: text.substring(start, i),
          column: start + 1,
          line: line,
        ));
        start = -1;
      }
    } else if (start < 0) {
      start = i;
    }
  }
  return out;
}

bool _isSpace(int unit) => unit == 0x20 || (unit >= 0x09 && unit <= 0x0d);

// ---------------------------------------------------------------------------
// PCF
// ---------------------------------------------------------------------------

/// iCE40 PCF. `#` starts a comment anywhere on the line. `set_io` takes
/// flags (`-pullup` and `-pullup_resistor` take a value; `-nowarn`,
/// `--warn-no-port` and any other flag stand alone), then the port and the
/// pin. `set_frequency` is read and names no port.
class _PcfReader extends _Reader {
  @override
  void line(String raw, int number) {
    final hash = raw.indexOf('#');
    final text = hash >= 0 ? raw.substring(0, hash) : raw;
    final words = _words(text, number);
    if (words.isEmpty) return;
    switch (words.first.text) {
      case 'set_io':
        var i = 1;
        while (i < words.length && words[i].text.startsWith('-')) {
          final flag = words[i].text;
          if (flag == '-pullup' || flag == '-pullup_resistor') i++;
          i++;
        }
        if (i > words.length - 2) {
          addUnparsed(number, words.first.column, text);
          return;
        }
        addEntry(words[i], words[i + 1].text);
      case 'set_frequency':
        if (words.length < 3) addUnparsed(number, words.first.column, text);
      default:
        addUnparsed(number, words.first.column, text);
    }
  }
}

// ---------------------------------------------------------------------------
// LPF
// ---------------------------------------------------------------------------

/// ECP5 LPF. Comments start at `#` or `//`. A statement runs to a `;` and may
/// span lines. `LOCATE COMP "<port>" SITE "<pin>"` places a port;
/// `IOBUF PORT "<port>" <attr>=<value>...` names one. `BLOCK`, `SYSCONFIG`
/// and `FREQUENCY` are read and name no port. Double quotes around a name are
/// removed.
class _LpfReader extends _Reader {
  final List<_Word> _statement = <_Word>[];
  int _statementLine = 0;

  @override
  void line(String raw, int number) {
    var text = raw;
    final hash = text.indexOf('#');
    if (hash >= 0) text = text.substring(0, hash);
    final slashes = text.indexOf('//');
    if (slashes >= 0) text = text.substring(0, slashes);

    var start = -1;
    void endWord(int end) {
      if (start < 0) return;
      if (_statement.isEmpty) _statementLine = number;
      _statement.add((
        text: text.substring(start, end),
        column: start + 1,
        line: number,
      ));
      start = -1;
    }

    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit == 0x3b) {
        // ';' ends the word and the statement.
        endWord(i);
        _finishStatement();
      } else if (_isSpace(unit)) {
        endWord(i);
      } else if (start < 0) {
        start = i;
      }
    }
    endWord(text.length);
  }

  @override
  ConstraintParseResult finish() {
    if (_statement.isNotEmpty) {
      addUnparsed(
        _statementLine,
        _statement.first.column,
        '${_statement.map((w) => w.text).join(' ')} (no terminating ";")',
      );
      _statement.clear();
    }
    return super.finish();
  }

  /// [text] with its double quotes removed, or `null` when it opens a quote
  /// it does not close (nextpnr: "expected '"' at end of string").
  static String? _unquote(String text) {
    if (!text.startsWith('"')) return text;
    if (text.length < 2 || !text.endsWith('"')) return null;
    return text.substring(1, text.length - 1);
  }

  /// The port name [unquoted] as a word positioned at the first character of
  /// the name, inside the quotes when it had them.
  static _Word _nameWord(_Word written, String unquoted) => (
    text: unquoted,
    column: written.column + (written.text.startsWith('"') ? 1 : 0),
    line: written.line,
  );

  void _finishStatement() {
    final words = List<_Word>.of(_statement);
    _statement.clear();
    if (words.isEmpty) return;
    final text = words.map((w) => w.text).join(' ');
    final line = _statementLine;
    switch (words.first.text) {
      case 'LOCATE':
        if (words.length != 5 ||
            words[1].text != 'COMP' ||
            words[3].text != 'SITE') {
          addUnparsed(line, words.first.column, text);
          return;
        }
        final port = _unquote(words[2].text);
        final pin = _unquote(words[4].text);
        if (port == null || port.isEmpty || pin == null) {
          addUnparsed(line, words.first.column, text);
          return;
        }
        addEntry(_nameWord(words[2], port), pin);
      case 'IOBUF':
        if (words.length < 3 || words[1].text != 'PORT') {
          addUnparsed(line, words.first.column, text);
          return;
        }
        final port = _unquote(words[2].text);
        if (port == null || port.isEmpty) {
          addUnparsed(line, words.first.column, text);
          return;
        }
        addEntry(_nameWord(words[2], port), null);
      case 'BLOCK' || 'SYSCONFIG' || 'FREQUENCY':
        break;
      default:
        addUnparsed(line, words.first.column, text);
    }
  }
}

// ---------------------------------------------------------------------------
// CST
// ---------------------------------------------------------------------------

/// Gowin CST. One statement per line, starting in column 1: nextpnr matches
/// each whole line against a fixed set of forms. `IO_LOC "<port>" <pin>;`
/// places a port (a second, comma-separated pin is a differential pair's
/// other half and is not read here); `IO_PORT "<port>" <attr>=<value>...;`
/// names one. `INS_LOC`, `CLOCK_LOC` and `USE_ADC_SRC` are read and name no
/// port. A line starting `//` is a comment.
class _CstReader extends _Reader {
  static final RegExp _ioLoc = RegExp(
    '^IO_LOC +"([^"]+)" +([^ ,;]+)(, *[^ ;]+)? *;',
  );
  static final RegExp _ioPort = RegExp('^IO_PORT +"([^"]+)" +([^;]+;)');
  static final RegExp _insLoc = RegExp(
    r'^INS_LOC +"([^"]+)" +(R[0-9]+C[0-9]+\[[0-9]\]\[[AB]\] *;|'
    r'(TOP|RIGHT|BOTTOM|LEFT)SIDE\[[01]\] *;*)',
  );
  static final RegExp _clockLoc = RegExp(
    r'^CLOCK_LOC +"([^"]+)" +BUF[GS](\[[0-7]\])?[^;]*;',
  );
  static final RegExp _adcSrc = RegExp(
    '^USE_ADC_SRC +bus[0-9] +IO[TRBL][0-9]+ *;',
  );

  @override
  void line(String raw, int number) {
    final text = raw.trimRight();
    if (text.isEmpty) return;

    final ioLoc = _ioLoc.firstMatch(text);
    if (ioLoc != null) {
      addEntry((
        text: ioLoc.group(1)!,
        column: text.indexOf('"') + 2,
        line: number,
      ), ioLoc.group(2));
      return;
    }
    final ioPort = _ioPort.firstMatch(text);
    if (ioPort != null) {
      addEntry((
        text: ioPort.group(1)!,
        column: text.indexOf('"') + 2,
        line: number,
      ), null);
      return;
    }
    if (_insLoc.hasMatch(text) ||
        _clockLoc.hasMatch(text) ||
        _adcSrc.hasMatch(text)) {
      return;
    }
    if (text.startsWith('//')) return;
    addUnparsed(number, 1, text);
  }
}
