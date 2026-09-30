// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/engine_reported_path.dart';

/// Parser for the `slang` SystemVerilog compiler's diagnostic output.
///
/// Slang has two relevant emission modes:
///
/// 1. **JSON** (`--diag-json <file|->`, upstream's `JsonDiagnosticClient`,
///    available since slang 8.0): a single pretty-printed JSON **array**
///    of diagnostic objects. Verified against slang 11.0.0; the upstream
///    writer is byte-identical from 8.0 through 11.0. Each element is
///
///    ```json
///    {
///      "severity": "warning",
///      "message": "unused variable 'never_used'",
///      "optionName": "unused-variable",
///      "location": "top.sv:8:15",
///      "symbolPath": "top.never_used"
///    }
///    ```
///
///    `location` is a **`file:line:column` string**, not an object, and
///    the rule id lives in `optionName` (the `-W` name, absent on
///    diagnostics that have no warning flag — errors, typically).
/// 2. **Text** (default): GCC/Clang-style
///    `file:line:col: severity: msg [-Wrule]` headers, followed by
///    source-context lines that begin with whitespace and a caret line
///    (`^~~`). The fallback for slang < 8.0, which has no JSON mode at
///    all.
///
/// Both modes therefore yield the *same* rule vocabulary — slang's `-W`
/// option names — so `slang/unused-variable` is the namespaced id
/// whichever mode produced it, and it matches
/// `lib/data/rules/slang.json` one-for-one.
///
/// For tolerance the JSON path also accepts a newline-delimited stream
/// of bare objects and the older `code` spelling of the rule field,
/// stripping a `slang::diag::` or `-W` prefix when present.
class SlangParser {
  /// Creates a [SlangParser]. [rootPath] resolves relative paths
  /// reported by the engine to absolute paths so the violation table
  /// can compare paths across engines without ambiguity.
  SlangParser({required this.rootPath});

  /// Absolute path to the project root.
  final String rootPath;

  /// Engine ID used for [Violation.engineId] and the namespaced rule
  /// prefix.
  static const String engineId = 'slang';

  // GCC/Clang-style header line. The severity word is required; the
  // rule code (`[-Wfoo]` or `[some::code]`) is optional and not always
  // emitted by every slang build.
  static final RegExp _textHeader = RegExp(
    r'^(?<file>.+?):(?<line>\d+):(?<col>\d+):\s+'
    r'(?<severity>warning|error|note|info|fatal):\s+'
    '(?<message>.*?)'
    r'(?:\s+\[(?<rule>[\w\-:/]+)\])?\s*$',
  );

  /// Parse [lines] in JSON-diagnostics mode.
  ///
  /// The `--diag-json` payload is a pretty-printed array that spans many
  /// lines, so this is not a line-at-a-time parse: the scanner finds each
  /// balanced JSON block (`[…]` or `{…}`), decodes it, and treats
  /// everything outside a block as text-mode output. That makes the
  /// method correct whether slang wrote an array, a newline-delimited
  /// object stream, or interleaved its human-readable banner (`Top level
  /// design units:` / `Build succeeded: …`) around the JSON — which it
  /// does unless `-q` is passed.
  ///
  /// The log-and-continue contract: a JSON block that
  /// fails to decode, an element that carries no usable location, and a
  /// text-mode line that matches no diagnostic header are **skipped,
  /// never fatal**. When [onUnrecognized] is supplied, each such
  /// (non-blank) line is reported verbatim so the caller can surface it
  /// as a SARIF `toolExecutionNotifications` entry instead of dropping
  /// it silently.
  List<Violation> parseJsonLines(
    List<String> lines, {
    void Function(String line)? onUnrecognized,
  }) {
    final out = <Violation>[];
    final textBuffer = <String>[];

    void flushText() {
      if (textBuffer.isEmpty) return;
      out.addAll(
        parseText(
          List<String>.from(textBuffer),
          onUnrecognized: onUnrecognized,
        ),
      );
      textBuffer.clear();
    }

    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        i++;
        continue;
      }
      final lead = line.trimLeft();
      if (lead.startsWith('[') || lead.startsWith('{')) {
        final block = _scanJsonBlock(lines, i);
        if (block != null) {
          // Flush any pending text-mode block first so we don't lose
          // diagnostics that arrived in text format ahead of the JSON.
          flushText();
          _decodeBlock(block.text, out, onUnrecognized);
          if (block.trailing.trim().isNotEmpty) {
            textBuffer.add(block.trailing);
          }
          i = block.endLine + 1;
          continue;
        }
      }
      textBuffer.add(line);
      i++;
    }
    flushText();
    return out;
  }

  /// Decodes one balanced JSON block into violations, appending to [out].
  void _decodeBlock(
    String text,
    List<Violation> out,
    void Function(String line)? onUnrecognized,
  ) {
    final dynamic decoded;
    try {
      decoded = json.decode(text);
    } on FormatException {
      onUnrecognized?.call(text);
      return;
    }
    final elements = decoded is List ? decoded : <dynamic>[decoded];
    for (final element in elements) {
      if (element is! Map<String, dynamic>) {
        onUnrecognized?.call(json.encode(element));
        continue;
      }
      final v = _violationFromMap(element);
      if (v != null) {
        out.add(v);
      } else {
        onUnrecognized?.call(json.encode(element));
      }
    }
  }

  /// Scans forward from [start] for one balanced JSON block, returning
  /// its text, the index of the line the block ends on, and whatever
  /// followed it on that line. Returns `null` when the block never
  /// closes (truncated output), so the caller can fall back to text.
  static ({String text, int endLine, String trailing})? _scanJsonBlock(
    List<String> lines,
    int start,
  ) {
    final buf = StringBuffer();
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var li = start; li < lines.length; li++) {
      final line = lines[li];
      if (li > start) buf.write('\n');
      for (var ci = 0; ci < line.length; ci++) {
        final ch = line[ci];
        buf.write(ch);
        if (escaped) {
          escaped = false;
          continue;
        }
        if (inString) {
          if (ch == r'\') {
            escaped = true;
          } else if (ch == '"') {
            inString = false;
          }
          continue;
        }
        switch (ch) {
          case '"':
            inString = true;
          case '[':
          case '{':
            depth++;
          case ']':
          case '}':
            depth--;
            if (depth == 0) {
              return (
                text: buf.toString(),
                endLine: li,
                trailing: line.substring(ci + 1),
              );
            }
        }
      }
    }
    return null;
  }

  /// Parse [lines] in text mode (GCC/Clang-style diagnostics).
  ///
  /// Slang's text format emits a header line followed by source-
  /// context lines indented with spaces; we treat consecutive
  /// non-header indented lines as continuations of the previous
  /// violation and preserve them in `Violation.raw['slang.context']`.
  List<Violation> parseText(
    List<String> lines, {
    void Function(String line)? onUnrecognized,
  }) {
    final out = <Violation>[];
    _PendingSlang? pending;
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

  /// Lowers one decoded diagnostic object to a [Violation], or `null`
  /// when it carries no usable message/location.
  Violation? _violationFromMap(Map<String, dynamic> decoded) {
    final message = decoded['message'];
    if (message is! String) return null;
    final location = _parseLocation(decoded['location']);
    if (location == null) return null;
    final severity = _mapSeverity(
      (decoded['severity'] is String ? decoded['severity'] as String : null) ??
          'warning',
    );
    // `optionName` is what slang 8.0+ writes (the `-W` name). `code` is
    // accepted as a tolerated alternate spelling.
    final option = decoded['optionName'] ?? decoded['code'];
    final rule = option is String && option.isNotEmpty
        ? _stripCodePrefix(option)
        : 'UNCLASSIFIED';
    return Violation(
      engineId: engineId,
      ruleId: '$engineId/$rule',
      severity: severity,
      message: message.trim(),
      location: location,
      raw: <String, dynamic>{
        for (final entry in decoded.entries) entry.key: entry.value,
      },
    );
  }

  /// Reads slang's `location` field, which is a `"file:line:column"`
  /// string in every release that has a JSON mode (8.0 through 11.0).
  /// A `{"file","line","column"}` object is also accepted.
  ///
  /// The string form is split from the **right** so a Windows path
  /// (`C:\rtl\top.sv:8:15`) keeps its drive-letter colon.
  SourceLocation? _parseLocation(Object? raw) {
    if (raw is Map<String, dynamic>) {
      final file = raw['file'];
      final lineNum = raw['line'];
      final col = raw['column'];
      if (file is! String || lineNum is! int || lineNum < 1) return null;
      final resolved = _absolute(file);
      if (resolved == null) return null;
      return SourceLocation(
        file: resolved,
        line: lineNum,
        column: col is int && col >= 1 ? col : 1,
      );
    }
    if (raw is! String || raw.isEmpty) return null;
    final lastColon = raw.lastIndexOf(':');
    if (lastColon <= 0) return null;
    final tail = raw.substring(lastColon + 1);
    final prevColon = raw.lastIndexOf(':', lastColon - 1);
    // `file:line:column` — the common case.
    if (prevColon > 0) {
      final lineNum = int.tryParse(raw.substring(prevColon + 1, lastColon));
      final col = int.tryParse(tail);
      if (lineNum != null && lineNum >= 1 && col != null) {
        final resolved = _absolute(raw.substring(0, prevColon));
        if (resolved == null) return null;
        return SourceLocation(
          file: resolved,
          line: lineNum,
          column: col < 1 ? 1 : col,
        );
      }
    }
    // `file:line` — no column (include-stack entries use this shape).
    final lineOnly = int.tryParse(tail);
    if (lineOnly == null || lineOnly < 1) return null;
    final resolvedTail = _absolute(raw.substring(0, lastColon));
    if (resolvedTail == null) return null;
    return SourceLocation(
      file: resolvedTail,
      line: lineOnly,
      column: 1,
    );
  }

  _PendingSlang? _fromHeader(RegExpMatch m) {
    final file = m.namedGroup('file');
    final lineStr = m.namedGroup('line');
    final colStr = m.namedGroup('col');
    final severity = m.namedGroup('severity') ?? 'warning';
    final rule = m.namedGroup('rule');
    final message = (m.namedGroup('message') ?? '').trim();
    if (file == null || lineStr == null || colStr == null) return null;
    final lineNum = int.tryParse(lineStr);
    if (lineNum == null || lineNum < 1) return null;
    final resolved = _absolute(file);
    if (resolved == null) return null;
    final col = int.tryParse(colStr) ?? 1;
    final ruleId = rule != null && rule.isNotEmpty
        ? _stripCodePrefix(rule)
        : 'UNCLASSIFIED';
    return _PendingSlang(
      ruleId: '$engineId/$ruleId',
      severity: _mapSeverity(severity),
      message: message,
      location: SourceLocation(
        file: resolved,
        line: lineNum,
        column: col < 1 ? 1 : col,
      ),
    );
  }

  /// Strip slang's `slang::diag::` or `-W` prefixes so the namespaced
  /// rule id stays readable in the table.
  static String _stripCodePrefix(String code) {
    var c = code;
    const longPrefix = 'slang::diag::';
    if (c.startsWith(longPrefix)) {
      c = c.substring(longPrefix.length);
    }
    if (c.startsWith('-W')) {
      c = c.substring(2);
    }
    return c;
  }

  Severity _mapSeverity(String word) {
    switch (word.toLowerCase()) {
      case 'error':
      case 'fatal':
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

class _PendingSlang {
  _PendingSlang({
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
      engineId: SlangParser.engineId,
      ruleId: ruleId,
      severity: severity,
      message: message,
      location: location,
      raw: <String, dynamic>{
        if (context.isNotEmpty) 'slang.context': List<String>.from(context),
      },
    );
  }
}
