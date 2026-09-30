// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:meta/meta.dart';

/// One source-embedded waiver block.
///
/// Represents a `// verilator lint_off RULE` … `// verilator lint_on
/// RULE` pair extracted from a source file. Spans 1-indexed
/// inclusive line ranges.
@immutable
class PragmaWaiver {
  /// Creates a [PragmaWaiver].
  const PragmaWaiver({
    required this.file,
    required this.ruleLocalId,
    required this.startLine,
    required this.endLine,
  });

  /// Absolute path of the source file the pragma lives in.
  final String file;

  /// Engine-local rule id (without the `verilator/` namespace).
  final String ruleLocalId;

  /// 1-indexed first line covered by the waiver.
  final int startLine;

  /// 1-indexed last line covered by the waiver.
  final int endLine;

  /// The engine-namespaced rule id this waiver matches.
  String get namespacedRuleId => 'verilator/$ruleLocalId';

  /// Whether [line] (1-indexed) falls inside the waiver range.
  bool covers(int line) => line >= startLine && line <= endLine;

  @override
  bool operator ==(Object other) =>
      other is PragmaWaiver &&
      other.file == file &&
      other.ruleLocalId == ruleLocalId &&
      other.startLine == startLine &&
      other.endLine == endLine;

  @override
  int get hashCode => Object.hash(file, ruleLocalId, startLine, endLine);

  @override
  String toString() => 'PragmaWaiver($file:$startLine-$endLine, $ruleLocalId)';
}

/// [LineRangeMap.waivers] grouped by `(file, ruleLocalId)`, each group in
/// declaration order.
typedef _RangeIndex = Map<(String, String), List<PragmaWaiver>>;

/// Per-instance [_RangeIndex] for [LineRangeMap.matchFor]. An [Expando] so
/// the map keeps its `const` constructor; weak on its key, so a map dropped
/// at the end of a run takes its index with it.
final Expando<_RangeIndex> _rangeIndexCache = Expando<_RangeIndex>(
  'pragmaRangeIndex',
);

/// Every pragma-waiver range in a project, looked up by `(file, line,
/// rule)`. Used by the waiver-matching transformer to mark violations
/// suppressed when their triple falls inside a range.
@immutable
class LineRangeMap {
  /// Creates a [LineRangeMap]. [waivers] must not change afterwards: the
  /// lookup index is built from it once, on the first [matchFor].
  const LineRangeMap(this.waivers);

  /// Empty map — convenience for tests and the no-pragma case.
  static const LineRangeMap empty = LineRangeMap(<PragmaWaiver>[]);

  /// Every waiver in declaration order.
  final List<PragmaWaiver> waivers;

  /// The first waiver, in declaration order, that covers [line] of
  /// [ruleLocalId] in [file]; `null` when none does.
  ///
  /// Runs once per violation on every lint run — including a cache hit,
  /// where the engine is skipped and this transformer step is most of the
  /// remaining work — so it must not scan the project's every pragma. The
  /// candidates come from an index grouped by `(file, ruleLocalId)`, built
  /// once per map: at 50,000 violations and 1,000 pragmas the scan took
  /// about 130 ms per run and grew linearly with the pragma count.
  PragmaWaiver? matchFor({
    required String file,
    required int line,
    required String ruleLocalId,
  }) {
    if (waivers.isEmpty) return null;
    final index = _rangeIndexCache[this] ??= _buildIndex(waivers);
    final candidates = index[(file, ruleLocalId)];
    if (candidates == null) return null;
    for (final w in candidates) {
      if (w.covers(line)) return w;
    }
    return null;
  }

  static _RangeIndex _buildIndex(List<PragmaWaiver> waivers) {
    final index = <(String, String), List<PragmaWaiver>>{};
    for (final w in waivers) {
      (index[(w.file, w.ruleLocalId)] ??= <PragmaWaiver>[]).add(w);
    }
    return index;
  }
}

/// Reads `// verilator lint_off RULE` / `// verilator lint_on RULE`
/// directives out of one or more source files and returns the resulting
/// [LineRangeMap].
///
/// **Recognized syntax** (case-sensitive, regex-driven so trailing
/// comments and surrounding whitespace are tolerated):
///
/// ```verilog
/// // verilator lint_off RULE
/// /* verilator lint_off RULE */
/// // verilator lint_on RULE
/// /* verilator lint_on RULE */
/// ```
///
/// A `lint_off` without a matching `lint_on` is taken to extend to
/// end-of-file. Multiple distinct rules can be suppressed by stacking
/// pragmas — each rule has its own independent range stack.
class PragmaWaiverReader {
  /// Creates a [PragmaWaiverReader].
  const PragmaWaiverReader({this.reader = const _DartIoLineReader()});

  /// Per-file line reader. Production uses dart:io; tests inject a
  /// fake.
  final LineReader reader;

  /// Regex matching the *opening* pragma form:
  /// `verilator lint_off RULE_NAME`. The directive can appear inside
  /// either `// …` or `/* … */` comments; both are matched.
  static final RegExp _offPattern = RegExp(
    r'verilator\s+lint_off\s+([A-Z0-9_]+)',
  );

  /// Regex matching the *closing* pragma form:
  /// `verilator lint_on RULE_NAME`.
  static final RegExp _onPattern = RegExp(
    r'verilator\s+lint_on\s+([A-Z0-9_]+)',
  );

  /// Reads pragma directives out of [files] and returns a
  /// [LineRangeMap] aggregating every detected waiver range.
  Future<LineRangeMap> readFiles(Iterable<String> files) async {
    final out = <PragmaWaiver>[];
    for (final file in files) {
      final lines = await reader.readLines(file);
      if (lines == null) continue;
      out.addAll(parseLines(file: file, lines: lines));
    }
    return LineRangeMap(List<PragmaWaiver>.unmodifiable(out));
  }

  /// Parse pragma directives out of the in-memory line list for
  /// [file]. Exposed for unit tests that want to avoid disk I/O.
  List<PragmaWaiver> parseLines({
    required String file,
    required List<String> lines,
  }) {
    final out = <PragmaWaiver>[];
    // Per-rule open ranges: ruleId → 1-indexed line where the
    // currently-open lint_off started.
    final open = <String, int>{};
    for (var i = 0; i < lines.length; i++) {
      final lineNum = i + 1;
      final line = lines[i];
      for (final m in _offPattern.allMatches(line)) {
        final rule = m.group(1)!;
        // If another lint_off is already open for this rule, close
        // it as `[startLine, lineNum - 1]` and re-open at lineNum so
        // both ranges still get captured. This matches the Verilator
        // semantic of nested/stacked pragmas.
        final prevStart = open[rule];
        if (prevStart != null && lineNum > prevStart) {
          out.add(
            PragmaWaiver(
              file: file,
              ruleLocalId: rule,
              startLine: prevStart,
              endLine: lineNum - 1,
            ),
          );
        }
        open[rule] = lineNum;
      }
      for (final m in _onPattern.allMatches(line)) {
        final rule = m.group(1)!;
        final startLine = open.remove(rule);
        if (startLine != null && lineNum >= startLine) {
          out.add(
            PragmaWaiver(
              file: file,
              ruleLocalId: rule,
              startLine: startLine,
              endLine: lineNum,
            ),
          );
        }
      }
    }
    // Anything still open at EOF extends to the last line.
    for (final entry in open.entries) {
      out.add(
        PragmaWaiver(
          file: file,
          ruleLocalId: entry.key,
          startLine: entry.value,
          endLine: lines.isEmpty ? entry.value : lines.length,
        ),
      );
    }
    return out;
  }
}

/// File-content reader abstraction for testability.
// ignore: one_member_abstracts
abstract class LineReader {
  /// Reads [file]'s lines, or returns `null` when unreadable.
  Future<List<String>?> readLines(String file);
}

class _DartIoLineReader implements LineReader {
  const _DartIoLineReader();

  @override
  Future<List<String>?> readLines(String file) async {
    try {
      final f = File(file);
      if (!f.existsSync()) return null;
      return (await f.readAsString()).split('\n');
    } on FileSystemException {
      return null;
    }
  }
}
