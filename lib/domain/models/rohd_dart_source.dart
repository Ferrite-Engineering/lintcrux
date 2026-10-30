// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A position in a Dart source file, as ROHD's source tracing recorded it.
@immutable
class RohdDartLocation {
  /// Creates a location.
  const RohdDartLocation({
    required this.file,
    required this.line,
    required this.column,
  });

  /// Reads the map [toJson] writes, or returns `null` for anything else.
  static RohdDartLocation? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final file = json['file'];
    final line = json['line'];
    final column = json['column'];
    if (file is! String || file.isEmpty || line is! int || line < 1) {
      return null;
    }
    return RohdDartLocation(
      file: file,
      line: line,
      column: column is int && column >= 1 ? column : 1,
    );
  }

  /// The Dart file: absolute when the package root was found, else relative to
  /// the package.
  final String file;

  /// 1-based line.
  final int line;

  /// 1-based column.
  final int column;

  /// The map stored under [RohdDartSource.rawKey].
  Map<String, Object> toJson() => <String, Object>{
    'file': file,
    'line': line,
    'column': column,
  };

  @override
  bool operator ==(Object other) =>
      other is RohdDartLocation &&
      other.file == file &&
      other.line == line &&
      other.column == column;

  @override
  int get hashCode => Object.hash(file, line, column);

  @override
  String toString() => '$file:$line:$column';
}

/// How a [RohdDartSource] was found.
enum RohdDartSourceKind {
  /// The finding's line is a position the trace recorded for a signal or an
  /// instance: where it is declared, driven or connected.
  exact,

  /// The line is a read or an expression the trace has no symbol for; this is
  /// the enclosing block or instance.
  enclosing,
}

/// Where in the Dart source the SystemVerilog under a finding came from.
///
/// ROHD 0.7 or later records this when source tracing is on. It is stored on
/// the violation under [rawKey] as plain JSON so it reaches SARIF with the
/// rest of the violation's properties.
@immutable
class RohdDartSource {
  /// Creates a Dart source.
  const RohdDartSource({
    required this.primary,
    required this.kind,
    this.symbol,
    this.fromInlineComment = false,
    this.calledFrom = const <RohdDartLocation>[],
  });

  /// The key in `Violation.raw` the transformer writes.
  static const String rawKey = 'lintcrux.rohdSource';

  /// Reads the value under [rawKey] of a violation's `raw` map, or returns
  /// `null` when there is none or it is not ours.
  static RohdDartSource? fromRaw(Map<String, dynamic> raw) {
    final value = raw[rawKey];
    if (value is! Map<String, Object?>) return null;
    final primary = RohdDartLocation.fromJson(value['primary']);
    if (primary == null) return null;
    final calledFrom = value['calledFrom'];
    return RohdDartSource(
      primary: primary,
      kind: value['kind'] == 'enclosing'
          ? RohdDartSourceKind.enclosing
          : RohdDartSourceKind.exact,
      symbol: value['symbol'] is String ? value['symbol']! as String : null,
      fromInlineComment: value['inline'] == true,
      calledFrom: <RohdDartLocation>[
        if (calledFrom is List<Object?>)
          for (final l in calledFrom)
            if (RohdDartLocation.fromJson(l) case final RohdDartLocation loc)
              loc,
      ],
    );
  }

  /// The innermost frame: the Dart line that created the signal or the
  /// instance.
  final RohdDartLocation primary;

  /// Whether [primary] is exact or the enclosing block or instance.
  final RohdDartSourceKind kind;

  /// The SystemVerilog name the match was made on, when there is one.
  final String? symbol;

  /// Whether the location came from the `// ROHD:` comment in the generated
  /// SystemVerilog rather than from the source-trace file.
  final bool fromInlineComment;

  /// The frames outward from [primary]: who called the code that created it,
  /// nearest caller first. The first is usually where the module was
  /// instantiated.
  final List<RohdDartLocation> calledFrom;

  /// The JSON stored under [rawKey].
  Map<String, Object> toJson() => <String, Object>{
    'primary': primary.toJson(),
    'kind': kind.name,
    'symbol': ?symbol,
    if (fromInlineComment) 'inline': true,
    if (calledFrom.isNotEmpty)
      'calledFrom': <Object>[for (final l in calledFrom) l.toJson()],
  };
}
