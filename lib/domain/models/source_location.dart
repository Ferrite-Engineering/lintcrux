// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A pointer into a source file used by [Violation] and friends.
///
/// `file` is normalized to an absolute path during parsing; relative
/// paths in engine output are resolved against the project root before
/// the [SourceLocation] is constructed. `line` and `column` are 1-based
/// to match every engine's native output and every editor's expectation
/// (the IDE shell-out command templates substitute them directly).
///
/// Maps onto SARIF's `physicalLocation.region` — see
/// [SARIF 2.1.0 §3.30](https://docs.oasis-open.org/sarif/sarif/v2.1.0/os/sarif-v2.1.0-os.html).
/// `endLine` / `endColumn` are optional so engines that only report a
/// single line and column don't have to fabricate range fields.
@immutable
class SourceLocation {
  /// Creates a [SourceLocation]. `line` and `column` must be positive
  /// when provided; `endLine` / `endColumn` are optional and default to
  /// `null` (meaning "engine did not provide a range").
  const SourceLocation({
    required this.file,
    required this.line,
    required this.column,
    this.endLine,
    this.endColumn,
  }) : assert(line >= 1, 'line must be 1-based and positive'),
       assert(column >= 1, 'column must be 1-based and positive');

  /// Absolute path to the source file.
  final String file;

  /// 1-based line of the primary marker.
  final int line;

  /// 1-based column of the primary marker.
  final int column;

  /// Optional 1-based end line. `null` means the engine reported a
  /// single point rather than a range.
  final int? endLine;

  /// Optional 1-based end column.
  final int? endColumn;

  /// Returns a copy with overridden fields. Pass an explicit `null`
  /// using a sentinel parameter only when the wrapper class actually
  /// needs to *clear* a field; no caller of this surface does.
  SourceLocation copyWith({
    String? file,
    int? line,
    int? column,
    int? endLine,
    int? endColumn,
  }) {
    return SourceLocation(
      file: file ?? this.file,
      line: line ?? this.line,
      column: column ?? this.column,
      endLine: endLine ?? this.endLine,
      endColumn: endColumn ?? this.endColumn,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SourceLocation &&
        other.file == file &&
        other.line == line &&
        other.column == column &&
        other.endLine == endLine &&
        other.endColumn == endColumn;
  }

  @override
  int get hashCode => Object.hash(file, line, column, endLine, endColumn);

  @override
  String toString() =>
      'SourceLocation($file:$line:$column'
      '${endLine != null ? '-$endLine:$endColumn' : ''})';
}
