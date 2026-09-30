// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/engine_reported_path.dart';

/// Parser for Verilator's `--lint-only` stderr output.
///
/// Verilator emits one violation as a sequence of lines:
///
/// ```text
/// %Warning-UNUSEDSIGNAL: top.sv:42:13: Signal is not used: 'unused_sig'
///                                    : ... In instance top
///    42 |   logic unused_sig;
///       |             ^~~~~~~~~~
///                              ... Use "/* verilator lint_off UNUSEDSIGNAL */" to disable
/// ```
///
/// The first line (`%Severity[-RULE]: file:line:col: message`) starts a
/// new violation. Every subsequent line that does *not* start with a `%`
/// is treated as a continuation of the current violation — these are
/// the source-context lines and ancillary notes. The parser preserves
/// them in [Violation.raw] under the `verilator.continuation` key so
/// the inspector pane can render them verbatim, and lifts
/// any embedded `file:line:col` it finds into
/// [Violation.relatedLocations] so click-to-source works on them.
///
/// Lines that don't match the violation pattern at all (engine banners,
/// progress prints) are silently ignored.
class VerilatorParser {
  /// Creates a [VerilatorParser]. `rootPath` resolves relative paths
  /// reported by the engine to absolute paths so the violation table
  /// can compare paths across engines without ambiguity.
  VerilatorParser({required this.rootPath});

  /// Absolute path to the project root — relative paths in engine
  /// output are resolved against this.
  final String rootPath;

  /// Engine ID used for [Violation.engineId] and the namespaced rule
  /// prefix.
  static const String engineId = 'verilator';

  // Matches the *first* line of a violation:
  //   %Severity[-RULE]: path:line:col: message
  // Severity is captured separately so we map it to [Severity]; RULE is
  // optional because old Verilator emits `%Error:` without a rule code.
  // Columns are optional (older Verilator versions omit them).
  // The optional `(?:[A-Za-z]:)?` prefix lets the file group span a Windows
  // drive-letter path (`C:\...`); without it the greedy `[^:]+` stops at the
  // colon in `C:` and the whole line fails to match, dropping every violation
  // on Windows and misreporting them as an engine failure. Mirrors the
  // drive-letter handling in [_embeddedLocationPattern] below.
  static final RegExp _headerPattern = RegExp(
    r'^%(?<severity>\w+)(?:-(?<rule>[A-Z0-9_]+))?:\s+'
    r'(?<file>(?:[A-Za-z]:)?[^:]+):(?<line>\d+)(?::(?<col>\d+))?:\s+'
    r'(?<message>.*)$',
  );

  // Verilator's end-of-run tally, e.g. `%Error: Exiting due to 2
  // warning(s)`. It carries no `file:line:col` so it is not a header, and
  // it is not part of the diagnostic above it either — it is benign noise
  // that must be dropped rather than glued onto the last violation's
  // continuation block or reported as an unrecognized line on every run
  // that finds anything.
  static final RegExp _summaryPattern = RegExp(
    r'^%\w+:\s+Exiting due to\b',
  );

  // Matches an embedded `file:line:col` (or `file:line`) inside a
  // continuation line; used to lift related locations.
  static final RegExp _embeddedLocationPattern = RegExp(
    r'(?<file>(?:[A-Za-z]:)?[\w./\-]+):(?<line>\d+)(?::(?<col>\d+))?',
  );

  /// Parse a complete Verilator stderr transcript.
  ///
  /// The log-and-continue contract: a line that is neither
  /// a recognized violation header nor a continuation of the open
  /// violation is **skipped, never fatal** — one unparseable line never
  /// fails the whole run. When [onUnrecognized] is supplied, every such
  /// skipped line is reported to it (verbatim) so the caller can surface it
  /// as a SARIF `toolExecutionNotifications` entry instead of dropping it
  /// silently. Blank lines are noise and are never reported.
  List<Violation> parse(
    List<String> lines, {
    void Function(String line)? onUnrecognized,
  }) {
    final out = <Violation>[];
    _PendingViolation? pending;

    for (final line in lines) {
      final headerMatch = _headerPattern.firstMatch(line);
      if (headerMatch != null) {
        // Flush the previous violation, if any.
        if (pending != null) {
          out.add(pending.build());
        }
        pending = _fromHeader(headerMatch);
        // A line that matched the header shape but carried an invalid
        // file/line is unparseable — surface it rather than dropping it.
        if (pending == null && line.isNotEmpty) {
          onUnrecognized?.call(line);
        }
        continue;
      }
      // A `%`-prefixed line that is not a header is never a continuation
      // of the diagnostic above it — Verilator only ever prefixes `%` on
      // a new message. Gluing it into the previous violation's
      // continuation block (which an earlier revision did, contradicting
      // this class's own doc comment) corrupts the inspector pane's
      // verbatim rendering and hides real failures such as
      // `%Error: Cannot find file containing module` behind an unrelated
      // warning. Close the pending violation and handle the line on its
      // own terms.
      if (line.startsWith('%')) {
        if (pending != null) {
          out.add(pending.build());
          pending = null;
        }
        if (!_summaryPattern.hasMatch(line)) {
          onUnrecognized?.call(line);
        }
        continue;
      }
      // Not a header line — treat as a continuation of the open
      // violation. Skip if no violation is open (engine banners, etc.).
      if (pending != null && line.isNotEmpty) {
        pending.addContinuation(line);
      } else if (line.isNotEmpty) {
        onUnrecognized?.call(line);
      }
    }
    if (pending != null) {
      out.add(pending.build());
    }
    return out;
  }

  _PendingViolation? _fromHeader(RegExpMatch m) {
    final severityWord = m.namedGroup('severity') ?? 'Warning';
    final rule = m.namedGroup('rule') ?? 'UNCLASSIFIED';
    final file = m.namedGroup('file') ?? '';
    final lineStr = m.namedGroup('line');
    final colStr = m.namedGroup('col');
    final message = m.namedGroup('message')?.trim() ?? '';
    if (file.isEmpty || lineStr == null) return null;
    final lineNum = int.tryParse(lineStr);
    if (lineNum == null || lineNum < 1) return null;
    final resolved = _absolute(file);
    if (resolved == null) return null;
    final col = colStr != null ? (int.tryParse(colStr) ?? 1) : 1;
    final severity = _mapSeverity(severityWord);
    final location = SourceLocation(
      file: resolved,
      line: lineNum,
      column: col < 1 ? 1 : col,
    );
    return _PendingViolation(
      engineId: engineId,
      ruleId: '$engineId/$rule',
      severity: severity,
      message: message,
      location: location,
      parser: this,
    );
  }

  Severity _mapSeverity(String word) {
    switch (word.toLowerCase()) {
      case 'error':
        return Severity.error;
      case 'warning':
        return Severity.warning;
      case 'note':
      case 'info':
        return Severity.note;
      default:
        return Severity.warning;
    }
  }

  /// [file] as the engine reported it, resolved to an absolute path and
  /// contained inside [rootPath]. `null` means the path was refused (see
  /// [resolveEngineReportedPath]); every caller turns that into "this line
  /// did not parse", so the refusal reaches `onUnrecognized` rather than
  /// reaching an editor argv.
  String? _absolute(String file) => resolveEngineReportedPath(file, rootPath);

  /// Lifts an embedded `file:line:col` reference out of a continuation
  /// line, resolving to an absolute path. Returns `null` if no
  /// location is present.
  SourceLocation? extractEmbeddedLocation(String line) {
    final m = _embeddedLocationPattern.firstMatch(line);
    if (m == null) return null;
    final file = m.namedGroup('file');
    final lineStr = m.namedGroup('line');
    if (file == null || lineStr == null) return null;
    final lineNum = int.tryParse(lineStr);
    if (lineNum == null || lineNum < 1) return null;
    final resolved = _absolute(file);
    if (resolved == null) return null;
    final col = int.tryParse(m.namedGroup('col') ?? '1') ?? 1;
    return SourceLocation(
      file: resolved,
      line: lineNum,
      column: col < 1 ? 1 : col,
    );
  }
}

class _PendingViolation {
  _PendingViolation({
    required this.engineId,
    required this.ruleId,
    required this.severity,
    required this.message,
    required this.location,
    required this.parser,
  });

  final String engineId;
  final String ruleId;
  final Severity severity;
  final String message;
  final SourceLocation location;
  final VerilatorParser parser;
  final List<String> continuation = <String>[];
  final List<SourceLocation> related = <SourceLocation>[];

  void addContinuation(String line) {
    continuation.add(line);
    final loc = parser.extractEmbeddedLocation(line);
    if (loc != null && loc != location && !related.contains(loc)) {
      related.add(loc);
    }
  }

  Violation build() {
    return Violation(
      engineId: engineId,
      ruleId: ruleId,
      severity: severity,
      message: message,
      location: location,
      relatedLocations: List<SourceLocation>.unmodifiable(related),
      raw: <String, dynamic>{
        if (continuation.isNotEmpty)
          'verilator.continuation': List<String>.from(continuation),
      },
    );
  }
}
