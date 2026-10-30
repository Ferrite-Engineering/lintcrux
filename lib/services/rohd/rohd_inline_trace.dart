// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Reader for the `// ROHD:` comments in ROHD-generated SystemVerilog.
///
/// With source tracing on, ROHD (0.7 or later) writes a compact comment after
/// each traced declaration, assignment and instantiation:
///
/// ```systemverilog
/// // Source files:
/// //   0: lib/design.dart
/// logic _a_add_b_carry;          // ROHD: 0:26:18 0:58:19
/// logic [7:0] partial;           // ROHD: 0:25:21 | 0:58:19
/// assign sum = partial;          // ROHD: 0:24:15 | 0:58:19
/// assign inner_pkt_valid = pkt[8];  // ROHD: ^
/// ```
///
/// Each comment is a stack of Dart frames, **innermost first**, written as
/// `fileIndex:line:column`, where the index is into the `// Source files:`
/// table of the module. To stay short each comment is encoded against the
/// previous one:
///
/// - `^` alone is the previous stack unchanged;
/// - a leading `^N` takes the previous stack's first N frames;
/// - `| frame` closes the new frames and rejoins the previous stack at that
///   frame, taking it and everything after it.
///
/// The comments skip port declarations and everything inside `always_comb`, so
/// the sidecar (see `rohd_sidecar.dart`) is the better source. This reader is
/// the fallback for SystemVerilog that arrives without one.
library;

import 'package:lintcrux/services/rohd/rohd_sidecar.dart';

/// A line of generated SystemVerilog that carries a trace comment.
class RohdInlineTrace {
  /// Creates a trace.
  const RohdInlineTrace({required this.line, required this.frames});

  /// 1-based line of the SystemVerilog.
  final int line;

  /// The Dart frames, **innermost first**, as `(file, line, column)` with the
  /// file already looked up in the module's table.
  final List<RohdInlineFrame> frames;
}

/// One Dart frame of an inline trace.
class RohdInlineFrame {
  /// Creates a frame.
  const RohdInlineFrame(this.file, this.line, this.column);

  /// The Dart file as the SystemVerilog's `// Source files:` table spells it,
  /// relative to the directory ROHD ran in.
  final String file;

  /// 1-based line.
  final int line;

  /// 1-based column.
  final int column;
}

final RegExp _tableHeader = RegExp(r'^\s*//\s*Source files:\s*$');
final RegExp _tableRow = RegExp(r'^\s*//\s+(\d+):\s*(\S.*?)\s*$');
final RegExp _traceComment = RegExp(r'//\s*ROHD:\s*(.*?)\s*$');

/// Reads every `// ROHD:` comment in [lines], in order.
///
/// Never throws: a comment that does not decode (a `^` with nothing before
/// it, a file index the table does not have) is skipped.
List<RohdInlineTrace> parseRohdInlineTraces(List<String> lines) {
  final out = <RohdInlineTrace>[];
  var table = <int, String>{};
  var readingTable = false;
  var previous = const <String>[];

  for (var i = 0; i < lines.length; i++) {
    final text = lines[i];
    if (_tableHeader.hasMatch(text)) {
      table = <int, String>{};
      readingTable = true;
      continue;
    }
    if (readingTable) {
      final row = _tableRow.firstMatch(text);
      if (row != null) {
        final index = int.tryParse(row.group(1)!);
        if (index != null) table[index] = row.group(2)!;
        continue;
      }
      readingTable = false;
    }

    final comment = _traceComment.firstMatch(text);
    if (comment == null) continue;
    final entries = _decode(comment.group(1)!, previous);
    if (entries == null || entries.isEmpty) continue;
    previous = entries;
    final frames = <RohdInlineFrame>[
      for (final entry in entries)
        if (_resolve(entry, table) case final RohdInlineFrame frame) frame,
    ];
    if (frames.isEmpty) continue;
    out.add(RohdInlineTrace(line: i + 1, frames: frames));
  }
  return out;
}

/// Expands one comment body against the previous stack, or returns `null`.
List<String>? _decode(String body, List<String> previous) {
  final tokens = body.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) return null;
  if (tokens.length == 1 && tokens.single == '^') {
    return previous.isEmpty ? null : previous;
  }

  final entries = <String>[];
  var index = 0;
  final first = tokens.first;
  if (first.startsWith('^')) {
    final count = int.tryParse(first.substring(1));
    if (count == null || count < 0 || count > previous.length) return null;
    entries.addAll(previous.take(count));
    index = 1;
  }

  var joined = false;
  for (; index < tokens.length; index++) {
    final token = tokens[index];
    if (token == '|') {
      if (index + 1 >= tokens.length) return null;
      final join = tokens[index + 1];
      // The suffix is the previous stack from the join frame outward.
      final at = previous.indexOf(join);
      if (at < 0) return null;
      entries.addAll(previous.skip(at));
      joined = true;
      break;
    }
    entries.add(token);
  }
  if (joined && index + 2 < tokens.length) return null;
  return entries;
}

RohdInlineFrame? _resolve(String entry, Map<int, String> table) {
  final frame = RohdFrame.parse(entry);
  if (frame == null) return null;
  final file = table[frame.fileIndex];
  if (file == null) return null;
  return RohdInlineFrame(file, frame.line, frame.column);
}
