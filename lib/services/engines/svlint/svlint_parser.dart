// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/engine_reported_path.dart';

/// Parser for the `svlint` lightweight SystemVerilog linter.
///
/// Svlint has no structured output mode. Its default report is a
/// rustc-style block per finding, which is the only svlint output that
/// carries the rule name (`--oneline` and `--github-actions` both drop it):
///
/// ```text
/// Fail: blocking_assignment_in_always_ff
///    --> top.sv:10:3
///    |
/// 10 |   always_ff @(posedge clk) begin
///    |   ^^^^^^^^^ hint  : Do not use blocking assignments within `always_ff`.
///    |             reason: Blocking assignment in `always_ff` may cause undefined event ordering.
///
/// ```
///
/// A tool error that points at a source position uses the same shape with
/// an `Error:` header (`Error: parse error` followed by `--> file:line:col`)
/// and is reported as an error-level violation, since a file svlint could
/// not parse was not linted. An `Error:` with no location (a source file
/// that does not exist) and the `Warning: Config file '.svlint.toml' is
/// not found` notice carry no finding and are surfaced through
/// [parse]'s `onUnrecognized` sink instead.
///
/// Svlint's rule field is a stable rule identifier (e.g.
/// `non_blocking_assignment_in_always_comb`), emitted directly into the
/// namespaced [Violation.ruleId] as `svlint/<rule>`. Svlint has no
/// severity of its own: every rule failure is a [Severity.warning] until a
/// project severity override says otherwise.
class SvlintParser {
  /// Creates a [SvlintParser].
  SvlintParser({required this.rootPath});

  /// Absolute path to the project root.
  final String rootPath;

  /// Engine ID used for [Violation.engineId] and the namespaced rule
  /// prefix.
  static const String engineId = 'svlint';

  /// Rule id given to an `Error:` block with a location whose header text
  /// yields no identifier characters.
  static const String _unclassifiedErrorRule = 'error';

  // `Fail: <rule>` opens a rule failure; `Error: <what>` opens a tool
  // error. Both are followed by the `-->` location line when svlint has a
  // position to report.
  static final RegExp _header = RegExp(
    r'^(?<kind>Fail|Error):\s+(?<text>.*?)\s*$',
  );

  // `   --> path:line:col`. The path is matched lazily so a Windows drive
  // letter or a `:` inside a directory name still leaves the two trailing
  // integers for line and column.
  static final RegExp _location = RegExp(
    r'^\s*-->\s+(?<file>.+?):(?<line>\d+):(?<col>\d+)\s*$',
  );

  // Every line of the block below the location opens with a gutter: an
  // optional source line number, then `|`. The body after the bar is the
  // source echo, the caret run with the hint, or the reason.
  static final RegExp _gutter = RegExp(r'^\s*\d*\s*\|(?<body>.*)$');
  static final RegExp _hint = RegExp(r'^\s*\^*\s*hint\s*:\s*(?<msg>.*?)\s*$');
  static final RegExp _reason = RegExp(
    r'^\s*\^*\s*reason\s*:\s*(?<msg>.*?)\s*$',
  );

  static final RegExp _nonIdentifier = RegExp('[^A-Za-z0-9]+');

  /// Parses svlint's default report in [lines].
  ///
  /// The log-and-continue contract: a line that is not part of a finding
  /// block, and a block that names no source position, are **skipped,
  /// never fatal**. When [onUnrecognized] is supplied, each such
  /// (non-blank) line is reported verbatim so the caller can surface it as
  /// a SARIF `toolExecutionNotifications` entry instead of dropping it
  /// silently.
  List<Violation> parse(
    List<String> lines, {
    void Function(String line)? onUnrecognized,
  }) {
    final out = <Violation>[];
    _PendingSvlint? pending;

    void flush() {
      final p = pending;
      if (p == null) return;
      pending = null;
      final v = p.build();
      if (v != null) {
        out.add(v);
      } else {
        onUnrecognized?.call(p.headerLine);
      }
    }

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        flush();
        continue;
      }
      final h = _header.firstMatch(line);
      if (h != null) {
        flush();
        pending = _PendingSvlint(
          isError: h.namedGroup('kind') == 'Error',
          headerText: h.namedGroup('text') ?? '',
          headerLine: line,
        );
        continue;
      }
      final p = pending;
      if (p != null) {
        if (p.location == null) {
          final loc = _location.firstMatch(line);
          if (loc != null) {
            // A refused path is still consumed as part of the block so the
            // gutter lines that follow do not surface one by one.
            p
              ..location = _locationFrom(loc)
              ..sawLocationLine = true;
            continue;
          }
        }
        final g = _gutter.firstMatch(line);
        if (g != null && p.sawLocationLine) {
          final body = g.namedGroup('body') ?? '';
          final hint = _hint.firstMatch(body);
          if (hint != null) {
            p.hint = hint.namedGroup('msg');
            continue;
          }
          final reason = _reason.firstMatch(body);
          if (reason != null) {
            p.reason = reason.namedGroup('msg');
            continue;
          }
          if (body.trim().isNotEmpty) p.context.add(body.trimRight());
          continue;
        }
        // Anything else ends the block.
        flush();
      }
      onUnrecognized?.call(line);
    }
    flush();
    return out;
  }

  SourceLocation? _locationFrom(RegExpMatch m) {
    final file = m.namedGroup('file');
    final lineNum = int.tryParse(m.namedGroup('line') ?? '');
    final col = int.tryParse(m.namedGroup('col') ?? '') ?? 1;
    if (file == null || lineNum == null || lineNum < 1) return null;
    final resolved = _absolute(file);
    if (resolved == null) return null;
    return SourceLocation(
      file: resolved,
      line: lineNum,
      column: col < 1 ? 1 : col,
    );
  }

  /// `parse error` becomes `parse_error`; the rule id must be an
  /// identifier because it is shown in the rule column and keyed by waivers.
  static String errorRuleFor(String headerText) {
    final slug = headerText
        .trim()
        .toLowerCase()
        .replaceAll(_nonIdentifier, '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.isEmpty ? _unclassifiedErrorRule : slug;
  }

  /// [file] as the engine reported it, resolved to an absolute path and
  /// contained inside [rootPath]. `null` means the path was refused (see
  /// [resolveEngineReportedPath]); every caller turns that into "this block
  /// did not parse", so the refusal reaches `onUnrecognized` rather than
  /// reaching an editor argv.
  String? _absolute(String file) => resolveEngineReportedPath(file, rootPath);
}

class _PendingSvlint {
  _PendingSvlint({
    required this.isError,
    required this.headerText,
    required this.headerLine,
  });

  final bool isError;
  final String headerText;
  final String headerLine;
  SourceLocation? location;
  bool sawLocationLine = false;
  String? hint;
  String? reason;
  final List<String> context = <String>[];

  /// `null` when the block carries no usable source position: an
  /// `Error:` with nothing to point at, or a path the containment check
  /// refused.
  Violation? build() {
    final loc = location;
    if (loc == null) return null;
    final String ruleId;
    final Severity severity;
    final String message;
    if (isError) {
      ruleId =
          '${SvlintParser.engineId}/'
          '${SvlintParser.errorRuleFor(headerText)}';
      severity = Severity.error;
      final h = hint;
      message = h == null || h.isEmpty ? headerText : '$headerText: $h';
    } else {
      final rule = headerText.isEmpty ? 'UNCLASSIFIED' : headerText;
      ruleId = '${SvlintParser.engineId}/$rule';
      severity = Severity.warning;
      final h = hint;
      message = h == null || h.isEmpty ? 'svlint rule "$rule" failed' : h;
    }
    final r = reason;
    return Violation(
      engineId: SvlintParser.engineId,
      ruleId: ruleId,
      severity: severity,
      message: message,
      location: loc,
      raw: <String, dynamic>{
        if (r != null && r.isNotEmpty) 'svlint.reason': r,
        if (context.isNotEmpty) 'svlint.context': List<String>.from(context),
      },
    );
  }
}
