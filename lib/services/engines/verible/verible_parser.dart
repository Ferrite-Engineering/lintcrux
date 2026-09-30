// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/engine_reported_path.dart';

/// Parser for Verible's `verible-verilog-lint` output.
///
/// Verible has two output modes:
///
/// 1. **JSON-line** (`--lint-output=jsonline`): one JSON object per
///    line with shape
///    `{"path", "line", "column", "rule", "severity", "message"}`.
///    Used by every supported Verible version; the engine prefers this
///    mode.
/// 2. **Text** (what every *upstream* `verible-verilog-lint` release
///    emits, and the only mode a stock binary supports):
///    `file:line:col-endCol: msg [Style: category] [rule]`. The column
///    range and the style-category tag are both optional so older
///    `file:line:col: msg [rule]` builds parse identically. Some
///    text-mode lines also carry an embedded `severity:` prefix; we
///    recognize it but normalize the rest to a single regex.
///
/// Both modes are line-oriented and emit one violation per line — no
/// multi-line continuation to handle (unlike Verilator).
class VeribleParser {
  /// Creates a [VeribleParser]. `rootPath` resolves relative paths
  /// reported by the engine to absolute paths so the violation table
  /// can compare paths across engines without ambiguity.
  VeribleParser({required this.rootPath});

  /// Absolute path to the project root.
  final String rootPath;

  /// Engine ID used for [Violation.engineId] and the namespaced rule
  /// prefix.
  static const String engineId = 'verible';

  // Matches the text-mode line. Severity is optional because most
  // text-mode emissions omit it; rule is at the end in brackets.
  //
  // The column is a RANGE on every upstream release
  // (`file.sv:8:24-42: message [rule]`) and a bare column on some older
  // builds (`file.sv:8:24: message [rule]`). `-COL2` is therefore
  // optional, with COL as the anchor column. Requiring the bare form is
  // what made the engine silently skip *every* line of upstream text
  // output and report a clean run — the
  // log-and-continue contract turned a 2,365-finding file into
  // "Completed, 0 violations".
  static final RegExp _textPattern = RegExp(
    r'^(?<file>.+?):(?<line>\d+):(?<col>\d+)(?:-(?<endCol>\d+))?:\s+'
    r'(?:(?<severity>warning|error|info|note):\s+)?'
    r'(?<message>.*?)(?:\s+\[(?<rule>[\w\-/.]+)\])?\s*$',
  );

  // Upstream emits a bracketed style-category tag ahead of the rule name
  // (`… message [Style: xyz] [rule-name]`). It is metadata, not part of
  // the diagnostic, so it is stripped from the message.
  static final RegExp _styleTagSuffix = RegExp(r'\s*\[Style:[^\]]*\]\s*$');

  /// Parse [lines] in JSON-line mode. Lines that do not parse as JSON
  /// fall back to the text parser so a Verible build that mixes modes
  /// (e.g. JSON-line for warnings, plain text for compiler errors)
  /// still produces a coherent violation list.
  ///
  /// The log-and-continue contract: a non-blank line that
  /// parses as neither JSON nor text is **skipped, never fatal**. When
  /// [onUnrecognized] is supplied, each such line is reported verbatim so
  /// the caller can surface it as a SARIF `toolExecutionNotifications`
  /// entry instead of dropping it silently.
  List<Violation> parseJsonLines(
    List<String> lines, {
    void Function(String line)? onUnrecognized,
  }) {
    final out = <Violation>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      Violation? v;
      if (line.startsWith('{')) {
        v = _parseJsonLine(line);
      }
      v ??= _parseTextLine(line);
      if (v != null) {
        out.add(v);
      } else {
        onUnrecognized?.call(line);
      }
    }
    return out;
  }

  /// Parse [lines] in text mode. See [parseJsonLines] for the
  /// [onUnrecognized] log-and-continue contract.
  List<Violation> parseText(
    List<String> lines, {
    void Function(String line)? onUnrecognized,
  }) {
    final out = <Violation>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final v = _parseTextLine(line);
      if (v != null) {
        out.add(v);
      } else {
        onUnrecognized?.call(line);
      }
    }
    return out;
  }

  Violation? _parseJsonLine(String line) {
    final dynamic decoded;
    try {
      decoded = json.decode(line);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final path = decoded['path'];
    final lineNum = decoded['line'];
    final col = decoded['column'];
    final rule = decoded['rule'] ?? decoded['url'];
    final severity = decoded['severity'];
    final message = decoded['message'];
    if (path is! String || lineNum is! int || message is! String) {
      return null;
    }
    if (lineNum < 1) return null;
    final resolved = _absolute(path);
    if (resolved == null) return null;
    final colInt = col is int && col >= 1 ? col : 1;
    final ruleStr = rule is String && rule.isNotEmpty ? rule : 'UNCLASSIFIED';
    return Violation(
      engineId: engineId,
      ruleId: '$engineId/$ruleStr',
      severity: _mapSeverity(severity is String ? severity : 'warning'),
      message: message.trim(),
      location: SourceLocation(
        file: resolved,
        line: lineNum,
        column: colInt,
      ),
      raw: <String, dynamic>{
        for (final entry in decoded.entries) entry.key: entry.value,
      },
    );
  }

  Violation? _parseTextLine(String line) {
    final m = _textPattern.firstMatch(line);
    if (m == null) return null;
    final file = m.namedGroup('file');
    final lineStr = m.namedGroup('line');
    final colStr = m.namedGroup('col');
    if (file == null || lineStr == null || colStr == null) return null;
    final lineNum = int.tryParse(lineStr);
    if (lineNum == null || lineNum < 1) return null;
    final resolved = _absolute(file);
    if (resolved == null) return null;
    final col = int.tryParse(colStr) ?? 1;
    final severity = m.namedGroup('severity') ?? 'warning';
    final rule = m.namedGroup('rule') ?? 'UNCLASSIFIED';
    final message = (m.namedGroup('message') ?? '')
        .replaceFirst(_styleTagSuffix, '')
        .trim();
    return Violation(
      engineId: engineId,
      ruleId: '$engineId/$rule',
      severity: _mapSeverity(severity),
      message: message,
      location: SourceLocation(
        file: resolved,
        line: lineNum,
        column: col < 1 ? 1 : col,
      ),
    );
  }

  Severity _mapSeverity(String word) {
    switch (word.toLowerCase()) {
      case 'error':
        return Severity.error;
      case 'warning':
        return Severity.warning;
      case 'info':
      case 'note':
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
}
