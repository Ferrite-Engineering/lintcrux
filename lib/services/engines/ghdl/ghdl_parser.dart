// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/engine_reported_path.dart';

/// Parser for GHDL's compiler-style stderr output.
///
/// GHDL emits one diagnostic per header line in a GCC-like shape. Note
/// that GHDL, unlike GCC/Clang, puts **no space** between the location
/// and the severity word, and echoes the offending source line verbatim
/// (no `NN |` line-number gutter):
///
/// ```text
/// design.vhd:17:14:warning: declaration of "rst" hides port "rst" [-Whide]
///     variable rst : integer;
///              ^
/// ```
///
/// Verified against GHDL 6.0.0 and 5.1.1 (llvm/mcode backends, macOS
/// arm64) — both emit the unspaced form byte-for-byte. The separator is
/// matched as `\s*` rather than `\s+` so a build that *does* insert a
/// space (a GCC-backend build, or a future upstream change) still
/// parses; requiring the space made the parser match nothing at all on
/// stock GHDL and report a clean run — the same class of silent
/// mis-parse the Verible parser once had.
///
/// The first line (`file:line[:col]:severity: message [flag]`) starts a
/// new diagnostic. Subsequent indented lines (source-context echo, caret
/// pointer, secondary "near here" notes) are treated as continuations of
/// the open diagnostic and preserved under
/// `Violation.raw['ghdl.continuation']` so the inspector can render them
/// verbatim, mirroring the [VerilatorParser] convention.
///
/// Severity words observed across GHDL versions:
///
/// - `error` / `fatal` → [Severity.error]
/// - `warning` → [Severity.warning]
/// - `note` / `info` / `remark` → [Severity.note]
///
/// Rule-id extraction: GHDL annotates many warnings with a flag in
/// brackets (e.g. `[-Wbinding]`, `[-Wreserved]`); the parser strips the
/// `-W` prefix when present so the namespaced rule id reads
/// `ghdl/binding` rather than `ghdl/-Wbinding`. Diagnostics that don't
/// carry a flag fall back to `ghdl/UNCLASSIFIED`.
class GhdlParser {
  /// Creates a [GhdlParser].
  GhdlParser({required this.rootPath});

  /// Absolute path to the project root; relative paths in GHDL output
  /// resolve against this.
  final String rootPath;

  /// Engine ID used for [Violation.engineId] and the namespaced rule
  /// prefix.
  static const String engineId = 'ghdl';

  // Matches the *first* line of a diagnostic:
  //   file:line[:col]:severity: message [flag]?
  // Column is optional (older GHDL builds omit it). The whitespace
  // between the location and the severity word is optional too: stock
  // GHDL emits none (verified on 6.0.0 and 5.1.1). The trailing flag
  // is the GCC-style annotation (e.g. `[-Wbinding]`).
  // The optional `(?:[A-Za-z]:)?` prefix lets the file group span a Windows
  // drive-letter path (`C:\...`); without it the greedy `[^:]+` stops at the
  // colon in `C:` and the diagnostic is dropped on Windows.
  static final RegExp _headerPattern = RegExp(
    '^(?<file>(?:[A-Za-z]:)?[^:]+):'
    r'(?<line>\d+)'
    r'(?::(?<col>\d+))?:\s*'
    r'(?<severity>error|fatal|warning|note|info|remark):\s+'
    '(?<message>.*?)'
    r'(?:\s+\[(?<flag>[^\]]+)\])?\s*$',
  );

  // GHDL's own tool-level messages, which name the *program* rather than
  // a source file and carry no line number:
  //
  //   ghdl:error: compilation error
  //   /opt/homebrew/bin/ghdl:error: unknown warning identifier: foo
  //
  // Real GHDL prints one of these after a failed analyse, so without this
  // they would be swallowed as a continuation of whichever diagnostic
  // happened to come last — rendering in the inspector as if they were
  // part of an unrelated warning. They are notifications, not
  // diagnostics.
  static final RegExp _toolMessagePattern = RegExp(
    r'^.*\bghdl(?:\.exe)?:\s*(?:error|warning|note|fatal):',
    caseSensitive: false,
  );

  /// Parse a complete GHDL stderr transcript.
  ///
  /// The log-and-continue contract: a line that is neither
  /// a recognized diagnostic header nor a continuation of the open
  /// diagnostic is **skipped, never fatal**. When [onUnrecognized] is
  /// supplied, each such skipped (non-blank) line is reported verbatim so
  /// the caller can surface it as a SARIF `toolExecutionNotifications`
  /// entry rather than dropping it silently.
  List<Violation> parse(
    List<String> lines, {
    void Function(String line)? onUnrecognized,
  }) {
    final out = <Violation>[];
    _PendingGhdl? pending;

    for (final line in lines) {
      final m = _headerPattern.firstMatch(line);
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
      // GHDL's own tool-level message: closes the open diagnostic and
      // surfaces as a notification rather than being absorbed into it.
      if (_toolMessagePattern.hasMatch(line)) {
        if (pending != null) {
          out.add(pending.build());
          pending = null;
        }
        onUnrecognized?.call(line);
        continue;
      }
      // Continuation: indented context / caret / "near here" notes.
      if (pending != null && line.isNotEmpty) {
        pending.continuation.add(line);
      } else if (line.isNotEmpty) {
        onUnrecognized?.call(line);
      }
    }
    if (pending != null) {
      out.add(pending.build());
    }
    return out;
  }

  _PendingGhdl? _fromHeader(RegExpMatch m) {
    final file = m.namedGroup('file');
    final lineStr = m.namedGroup('line');
    final colStr = m.namedGroup('col');
    final severity = m.namedGroup('severity') ?? 'warning';
    final message = (m.namedGroup('message') ?? '').trim();
    final flag = m.namedGroup('flag');
    if (file == null || lineStr == null) return null;
    final lineNum = int.tryParse(lineStr);
    if (lineNum == null || lineNum < 1) return null;
    final resolved = _absolute(file);
    if (resolved == null) return null;
    final col = colStr != null ? (int.tryParse(colStr) ?? 1) : 1;
    final rule = _ruleIdFromFlag(flag);
    return _PendingGhdl(
      ruleId: '$engineId/$rule',
      severity: _mapSeverity(severity),
      message: message,
      flag: flag,
      location: SourceLocation(
        file: resolved,
        line: lineNum,
        column: col < 1 ? 1 : col,
      ),
    );
  }

  /// Maps a bracketed flag like `-Wbinding` or `binding` to the
  /// engine-namespaced rule local id (`binding`). Returns
  /// `UNCLASSIFIED` when no flag was emitted.
  static String _ruleIdFromFlag(String? flag) {
    if (flag == null || flag.isEmpty) return 'UNCLASSIFIED';
    var f = flag;
    if (f.startsWith('-W')) f = f.substring(2);
    if (f.isEmpty) return 'UNCLASSIFIED';
    return f;
  }

  static Severity _mapSeverity(String word) {
    switch (word.toLowerCase()) {
      case 'error':
      case 'fatal':
        return Severity.error;
      case 'warning':
        return Severity.warning;
      case 'note':
      case 'info':
      case 'remark':
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

class _PendingGhdl {
  _PendingGhdl({
    required this.ruleId,
    required this.severity,
    required this.message,
    required this.location,
    this.flag,
  });

  final String ruleId;
  final Severity severity;
  final String message;
  final SourceLocation location;
  final String? flag;
  final List<String> continuation = <String>[];

  Violation build() {
    return Violation(
      engineId: GhdlParser.engineId,
      ruleId: ruleId,
      severity: severity,
      message: message,
      location: location,
      raw: <String, dynamic>{
        if (flag != null) 'ghdl.flag': flag,
        if (continuation.isNotEmpty)
          'ghdl.continuation': List<String>.from(continuation),
      },
    );
  }
}
