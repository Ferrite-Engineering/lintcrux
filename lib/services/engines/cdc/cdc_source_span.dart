// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A source position recovered from a Yosys `src` cell attribute.
///
/// **Why this exists at all.** A CDC finding without a real source position is
/// a finding you cannot waive. The waiver store keys on
/// `(ruleId, filePath, line range)`, so if every crossing anchors to
/// `sourceFiles.first` line 1 — which is what the engine did when the rules
/// first shipped — then waiving one `cdc/unsync-multi-bit` waives *all* of
/// them. That is not a partial feature, it is a wrong one: the user believes
/// they suppressed a single reviewed crossing and silently suppressed the rest
/// of the design's.
@immutable
class CdcSourceSpan {
  /// Creates a span.
  const CdcSourceSpan({
    required this.file,
    required this.line,
    required this.column,
  });

  /// Parses one Yosys `src` attribute value.
  ///
  /// Yosys writes `file:startLine.startCol-endLine.endCol`, and for a cell
  /// synthesized from several statements it writes **several** such spans
  /// joined by `|`. The first is taken: a `$procdff` merged from a multi-branch
  /// `always` block lists every contributing branch, and the first is the
  /// declaration site — the place a reader wants to land.
  ///
  /// Tolerates the shorter `file:line` form, which older Yosys releases and
  /// some frontends emit, and returns `null` for anything else rather than
  /// guessing. A wrong line number is worse than no line number: it sends the
  /// reader to unrelated code and quietly poisons any waiver written there.
  static CdcSourceSpan? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final first = raw.split('|').first.trim();
    if (first.isEmpty) return null;
    // Split on the LAST colon so a Windows path (`C:\rtl\top.v:12.3-14.5`)
    // keeps its drive letter.
    final colon = first.lastIndexOf(':');
    if (colon <= 0 || colon == first.length - 1) return null;
    final file = first.substring(0, colon);
    final position = first.substring(colon + 1);
    final startOfRange = position.split('-').first;
    final parts = startOfRange.split('.');
    final line = int.tryParse(parts.first);
    if (line == null || line < 1) return null;
    final column = parts.length > 1 ? int.tryParse(parts[1]) : null;
    return CdcSourceSpan(
      file: file,
      line: line,
      column: column != null && column >= 1 ? column : 1,
    );
  }

  /// Source file, exactly as Yosys recorded it.
  final String file;

  /// 1-based line.
  final int line;

  /// 1-based column.
  final int column;

  @override
  bool operator ==(Object other) =>
      other is CdcSourceSpan &&
      other.file == file &&
      other.line == line &&
      other.column == column;

  @override
  int get hashCode => Object.hash(file, line, column);

  @override
  String toString() => '$file:$line:$column';
}
