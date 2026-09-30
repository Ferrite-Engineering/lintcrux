// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/engine_reported_path.dart';

/// Parser for the `svlint` lightweight SystemVerilog linter.
///
/// Svlint emits one violation per line in two modes:
///
/// 1. **JSON** (`--output-format=json` / `-o json`): one JSON object per
///    line with shape
///    `{"path", "line", "column", "rule", "message", "hint"}`. This is
///    the preferred mode and the engine always asks for it; older
///    builds without JSON support fall back to the text mode below.
/// 2. **Text** (default): GCC-style `file:line:col: hint: rule: msg`.
///    Treated as the fallback when JSON-mode output is unavailable.
///
/// Svlint's rule field is a stable rule identifier (e.g.
/// `non_blocking_assignment_in_always_comb`) — emitted directly into
/// the namespaced [Violation.ruleId] as `svlint/<rule>`.
class SvlintParser {
  /// Creates a [SvlintParser].
  SvlintParser({required this.rootPath});

  /// Absolute path to the project root.
  final String rootPath;

  /// Engine ID used for [Violation.engineId] and the namespaced rule
  /// prefix.
  static const String engineId = 'svlint';

  // GCC/Clang-style header line for the text fallback. Svlint's text
  // output marks the severity tier with `Error:` / `Warning:` / `Info:`
  // (capitalised) prefixed onto the message, with the rule name in the
  // tail bracket.
  static final RegExp _textHeader = RegExp(
    '^(?<file>.+?):'
    r'(?<line>\d+):(?<col>\d+):\s+'
    r'(?<severity>Error|Warning|Info|Hint|Note):\s+'
    '(?<message>.*?)'
    r'(?:\s+\[(?<rule>[\w./\-]+)\])?\s*$',
  );

  /// Parse [lines] in JSON mode. Non-JSON lines fall back to text
  /// parsing so mixed-mode emissions still produce a coherent list.
  ///
  /// The log-and-continue contract: a `{`-prefixed line
  /// that fails JSON parsing, and a text-mode line that matches no
  /// header, are **skipped, never fatal**. When [onUnrecognized] is
  /// supplied, each such (non-blank) line is reported verbatim so the
  /// caller can surface it as a SARIF `toolExecutionNotifications` entry
  /// instead of dropping it silently.
  List<Violation> parseJsonLines(
    List<String> lines, {
    void Function(String line)? onUnrecognized,
  }) {
    final out = <Violation>[];
    final textBuffer = <String>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      if (line.startsWith('{')) {
        if (textBuffer.isNotEmpty) {
          out.addAll(
            parseText(
              List<String>.from(textBuffer),
              onUnrecognized: onUnrecognized,
            ),
          );
          textBuffer.clear();
        }
        final v = _parseJsonObject(line);
        if (v != null) {
          out.add(v);
        } else {
          onUnrecognized?.call(line);
        }
      } else {
        textBuffer.add(line);
      }
    }
    if (textBuffer.isNotEmpty) {
      out.addAll(parseText(textBuffer, onUnrecognized: onUnrecognized));
    }
    return out;
  }

  /// Parse [lines] in text mode (GCC-style fallback). Multi-line
  /// continuation context lines (caret + hint) are absorbed into
  /// `Violation.raw['svlint.context']`. See [parseJsonLines] for the
  /// [onUnrecognized] log-and-continue contract.
  List<Violation> parseText(
    List<String> lines, {
    void Function(String line)? onUnrecognized,
  }) {
    final out = <Violation>[];
    _PendingSvlint? pending;
    for (final line in lines) {
      final m = _textHeader.firstMatch(line);
      if (m != null) {
        if (pending != null) {
          out.add(pending.build());
        }
        pending = _fromHeader(m);
        if (pending == null && line.isNotEmpty) {
          onUnrecognized?.call(line);
        }
        continue;
      }
      if (pending != null && line.isNotEmpty) {
        pending.context.add(line);
      } else if (line.isNotEmpty) {
        onUnrecognized?.call(line);
      }
    }
    if (pending != null) {
      out.add(pending.build());
    }
    return out;
  }

  Violation? _parseJsonObject(String line) {
    final dynamic decoded;
    try {
      decoded = json.decode(line);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final file = decoded['path'];
    final lineNum = decoded['line'];
    final col = decoded['column'];
    final rule = decoded['rule'];
    final message = decoded['message'] ?? decoded['hint'];
    if (file is! String || lineNum is! int || rule is! String) {
      return null;
    }
    if (lineNum < 1) return null;
    final resolved = _absolute(file);
    if (resolved == null) return null;
    final colInt = col is int && col >= 1 ? col : 1;
    final msg = message is String ? message : 'svlint rule "$rule" matched';
    final severityRaw = decoded['severity'];
    final severity = severityRaw is String
        ? _mapSeverity(severityRaw)
        : Severity.warning;
    return Violation(
      engineId: engineId,
      ruleId: '$engineId/$rule',
      severity: severity,
      message: msg,
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

  _PendingSvlint? _fromHeader(RegExpMatch m) {
    final file = m.namedGroup('file');
    final lineStr = m.namedGroup('line');
    final colStr = m.namedGroup('col');
    final severity = m.namedGroup('severity') ?? 'Warning';
    final rule = m.namedGroup('rule');
    final message = (m.namedGroup('message') ?? '').trim();
    if (file == null || lineStr == null || colStr == null) return null;
    final lineNum = int.tryParse(lineStr);
    if (lineNum == null || lineNum < 1) return null;
    final resolved = _absolute(file);
    if (resolved == null) return null;
    final col = int.tryParse(colStr) ?? 1;
    final ruleLocal = (rule != null && rule.isNotEmpty) ? rule : 'UNCLASSIFIED';
    return _PendingSvlint(
      ruleId: '$engineId/$ruleLocal',
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
      case 'fatal':
        return Severity.error;
      case 'warning':
        return Severity.warning;
      case 'info':
      case 'hint':
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

class _PendingSvlint {
  _PendingSvlint({
    required this.ruleId,
    required this.severity,
    required this.message,
    required this.location,
  });

  final String ruleId;
  final Severity severity;
  final String message;
  final SourceLocation location;
  final List<String> context = <String>[];

  Violation build() {
    return Violation(
      engineId: SvlintParser.engineId,
      ruleId: ruleId,
      severity: severity,
      message: message,
      location: location,
      raw: <String, dynamic>{
        if (context.isNotEmpty) 'svlint.context': List<String>.from(context),
      },
    );
  }
}
