// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// One port reference in a constraint file.
@immutable
class ConstraintEntry {
  /// Creates an entry.
  const ConstraintEntry({
    required this.port,
    required this.line,
    required this.column,
    this.bit,
    this.pin,
  });

  /// The port name without any bit index.
  final String port;

  /// The bit index written after the name (`led[3]` gives 3), or `null` when
  /// the name carries none.
  final int? bit;

  /// The package pin the line places the port on, or `null` for a line that
  /// names the port without placing it (`IOBUF PORT`, `IO_PORT`).
  final String? pin;

  /// 1-based line of the statement.
  final int line;

  /// 1-based column of the port name.
  final int column;

  /// The name as written, `led[3]` or `clk`.
  String get written => bit == null ? port : '$port[$bit]';

  @override
  String toString() => 'ConstraintEntry($written -> $pin @ $line:$column)';
}

/// A line (or statement) the parser did not recognise.
@immutable
class UnparsedConstraintLine {
  /// Creates a record.
  const UnparsedConstraintLine({
    required this.line,
    required this.column,
    required this.text,
  });

  /// 1-based line where the text starts.
  final int line;

  /// 1-based column where the text starts.
  final int column;

  /// The text, trimmed and cut to a readable length.
  final String text;

  @override
  String toString() => 'UnparsedConstraintLine($line:$column "$text")';
}

/// What reading one constraint file produced.
@immutable
class ConstraintParseResult {
  /// Creates a result.
  const ConstraintParseResult({
    required this.entries,
    required this.unparsed,
  });

  /// Every port reference, in file order.
  final List<ConstraintEntry> entries;

  /// Everything the reader did not recognise, in file order.
  final List<UnparsedConstraintLine> unparsed;
}
