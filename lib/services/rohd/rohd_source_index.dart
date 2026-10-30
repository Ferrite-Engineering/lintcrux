// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:lintcrux/domain/models/rohd_dart_source.dart';
import 'package:lintcrux/services/rohd/rohd_inline_trace.dart';
import 'package:lintcrux/services/rohd/rohd_sidecar.dart';
import 'package:path/path.dart' as p;

/// The most outward frames kept on a [RohdDartSource.calledFrom].
const int kRohdMaxCalledFrom = 8;

/// The most lines an enclosing block or statement is followed.
const int _maxExtent = 2000;

/// One place in a generated SystemVerilog file that ROHD traced to Dart.
class _Anchor {
  _Anchor({
    required this.line,
    required this.frames,
    required this.symbol,
    required this.fromInline,
    this.isInstance = false,
  });

  /// 1-based line in the SystemVerilog.
  final int line;

  /// The Dart frames, innermost first, already resolved to files.
  final List<RohdDartLocation> frames;

  /// The SystemVerilog name, when the source gave one.
  final String? symbol;

  /// Whether this came from a `// ROHD:` comment.
  final bool fromInline;

  /// Whether the symbol is a submodule instance or a block, as opposed to a
  /// signal. When a block and a signal start on the same line the block is
  /// what encloses the lines after it.
  final bool isInstance;
}

/// Maps lines of one generated SystemVerilog file to the Dart that made them.
///
/// The order of preference is the order of trust:
///
/// 1. a position the sidecar recorded for the line itself: the line declares,
///    drives or connects a traced signal or instance (**exact**);
/// 2. the sidecar's nearest enclosing block or statement, found by following
///    `begin` / `end` from the position (**enclosing**): a read such as
///    `if(valid_bit)` has no symbol, but sits inside the `always_comb` the
///    sidecar does map;
/// 3. the same two steps over the `// ROHD:` comments in the file, for
///    SystemVerilog that arrives without a sidecar.
class RohdFileIndex {
  RohdFileIndex._(this._lines, this._sidecar, this._inline);

  /// Builds an index for tests and callers that already hold the pieces.
  ///
  /// [sidecars] are parsed sidecars, [sidecarDirs] the directory each was read
  /// from (parallel lists), used to find the Dart package.
  factory RohdFileIndex.build({
    required String svPath,
    required List<String> lines,
    required List<RohdSidecar> sidecars,
    required List<String> sidecarDirs,
  }) {
    final resolver = _DartPathResolver(svDir: p.dirname(svPath));
    final sidecarAnchors = <_Anchor>[];
    for (var i = 0; i < sidecars.length; i++) {
      sidecarAnchors.addAll(
        _sidecarAnchors(
          svPath,
          sidecars[i],
          resolver.forSidecar(sidecars[i], sidecarDirs[i]),
        ),
      );
    }
    final inlineAnchors = <_Anchor>[
      for (final trace in parseRohdInlineTraces(lines))
        _Anchor(
          line: trace.line,
          frames: <RohdDartLocation>[
            for (final f in trace.frames)
              RohdDartLocation(
                file: resolver.forInline().call(f.file),
                line: f.line,
                column: f.column,
              ),
          ],
          symbol: null,
          fromInline: true,
        ),
    ];
    return RohdFileIndex._(lines, sidecarAnchors, inlineAnchors);
  }

  final List<String> _lines;
  final List<_Anchor> _sidecar;
  final List<_Anchor> _inline;

  /// Whether the index holds anything to look up.
  bool get isEmpty => _sidecar.isEmpty && _inline.isEmpty;

  /// The Dart source for [line] (1-based) of the SystemVerilog, or `null`.
  ///
  /// [message] is the finding's text. When several symbols are traced to the
  /// same line, the one whose name the message mentions is chosen; otherwise
  /// the first the trace listed.
  RohdDartSource? lookup(int line, {String? message}) {
    for (final anchors in <List<_Anchor>>[_sidecar, _inline]) {
      final exact = anchors.where((a) => a.line == line).toList();
      if (exact.isNotEmpty) {
        return _source(
          _prefer(exact, message),
          RohdDartSourceKind.exact,
        );
      }
      final enclosing = _enclosing(anchors, line);
      if (enclosing != null) {
        return _source(enclosing, RohdDartSourceKind.enclosing);
      }
    }
    return null;
  }

  /// Several symbols can be traced to one line: a port connection puts the
  /// connected signal on the instance's own line. The symbol the finding names
  /// wins; with none named, an instance (the statement the line is) wins over
  /// a signal it merely mentions; then the order the trace listed them in.
  _Anchor _prefer(List<_Anchor> candidates, String? message) {
    if (candidates.length == 1) return candidates.first;
    if (message != null) {
      for (final a in candidates) {
        final name = a.symbol;
        if (name != null &&
            RegExp('\\b${RegExp.escape(name)}\\b').hasMatch(message)) {
          return a;
        }
      }
    }
    return candidates.firstWhere(
      (a) => a.isInstance,
      orElse: () => candidates.first,
    );
  }

  /// The innermost anchor whose block or statement contains [line].
  _Anchor? _enclosing(List<_Anchor> anchors, int line) {
    _Anchor? best;
    for (final a in anchors) {
      if (a.line >= line) continue;
      if (best != null) {
        if (a.line < best.line) continue;
        if (a.line == best.line && (best.isInstance || !a.isInstance)) {
          continue;
        }
      }
      if (_end(a.line) >= line) best = a;
    }
    return best;
  }

  final Map<int, int> _ends = <int, int>{};

  int _end(int start) => _ends[start] ??= _extentEnd(_lines, start);

  RohdDartSource _source(_Anchor anchor, RohdDartSourceKind kind) {
    final frames = anchor.frames;
    return RohdDartSource(
      primary: frames.first,
      kind: kind,
      symbol: anchor.symbol,
      fromInlineComment: anchor.fromInline,
      calledFrom: frames.skip(1).take(kRohdMaxCalledFrom).toList(),
    );
  }
}

List<_Anchor> _sidecarAnchors(
  String svPath,
  RohdSidecar sidecar,
  String Function(String) resolve,
) {
  final base = p.basename(svPath).toLowerCase();
  final names = <String>{
    for (final m in sidecar.modules)
      ...m.svFileNames.map((n) => n.toLowerCase()),
  };
  // A sidecar names the file it was written beside. When the linted file has
  // another name (`top.sv` for `Top.sv`) it still matches case-insensitively;
  // when it matches nothing but the sidecar describes exactly one file, that
  // file is this one renamed.
  final bool Function(RohdModule) accept;
  if (names.contains(base)) {
    accept = (m) => m.svFileNames.any((n) => n.toLowerCase() == base);
  } else if (names.length == 1) {
    accept = (m) => m.svFileNames.isNotEmpty;
  } else {
    return const <_Anchor>[];
  }

  final locations = <String, String>{
    for (var i = 0; i < sidecar.files.length; i++)
      '$i': resolve(sidecar.files[i]),
  };
  final anchors = <_Anchor>[];
  for (final module in sidecar.modules.where(accept)) {
    for (final symbol in module.symbols) {
      if (symbol.positions.isEmpty || symbol.frames.isEmpty) continue;
      final frames = <RohdDartLocation>[
        for (final f in symbol.frames.reversed)
          if (locations['${f.fileIndex}'] case final String file)
            RohdDartLocation(file: file, line: f.line, column: f.column),
      ];
      if (frames.isEmpty) continue;
      for (final position in symbol.positions) {
        anchors.add(
          _Anchor(
            line: position.line,
            frames: frames,
            symbol: symbol.name,
            fromInline: false,
            isInstance: symbol.isInstance,
          ),
        );
      }
    }
  }
  return anchors;
}

final RegExp _blockHead = RegExp(
  r'\b(always_comb|always_ff|always_latch|always|initial|final)\b',
);
final RegExp _opens = RegExp(r'\b(begin|fork|case|casez|casex)\b');
final RegExp _closes = RegExp(r'\b(end|join|join_any|join_none|endcase)\b');

String _code(String line) {
  final at = line.indexOf('//');
  return (at < 0 ? line : line.substring(0, at)).trim();
}

/// The last line (1-based) of the block or statement that starts at [start].
///
/// [start] may be a comment line that introduces what follows (ROHD writes
/// `//  combinational` above an `always_comb`). A procedural block runs until
/// its `begin` / `end` nesting returns to zero; anything else runs to the
/// first line holding a `;`.
int _extentEnd(List<String> lines, int start) {
  var s = start;
  while (s <= lines.length && _code(lines[s - 1]).isEmpty) {
    s++;
  }
  if (s > lines.length) return start;
  final limit = (s + _maxExtent).clamp(s, lines.length);
  final isBlock = _blockHead.hasMatch(_code(lines[s - 1]));
  var depth = 0;
  var opened = false;
  for (var i = s; i <= limit; i++) {
    final code = _code(lines[i - 1]);
    if (!isBlock) {
      if (code.contains(';')) return i;
      continue;
    }
    depth += _opens.allMatches(code).length;
    if (_opens.hasMatch(code)) opened = true;
    depth -= _closes.allMatches(code).length;
    if (opened && depth <= 0) return i;
    if (!opened && code.contains(';')) return i;
  }
  return limit;
}

/// Finds the Dart file a sidecar or comment names on this machine.
///
/// A path in a sidecar is relative to the Dart package that generated it
/// (`.dart_tool/../lib/design.dart`), and the package is not where the
/// SystemVerilog is: the file was generated, committed or copied somewhere
/// else. The package root is tried in this order, taking the first that holds
/// the file: the `packageRoot` the sidecar recorded, then each directory
/// above the sidecar, then each above the SystemVerilog. If none holds it the
/// nearest directory with a `pubspec.yaml` is used, so the location is still
/// a usable path, and failing that the sidecar's own directory.
class _DartPathResolver {
  _DartPathResolver({required this.svDir});

  final String svDir;

  String Function(String) forSidecar(RohdSidecar sidecar, String sidecarDir) {
    final roots = <String>[
      if (sidecar.packageRoot != null) sidecar.packageRoot!,
      ..._ancestors(sidecarDir),
      ..._ancestors(svDir),
    ];
    return (raw) => _resolve(raw, roots, sidecarDir);
  }

  String Function(String) forInline() {
    final roots = _ancestors(svDir);
    return (raw) => _resolve(raw, roots, svDir);
  }

  static List<String> _ancestors(String dir) {
    final out = <String>[];
    var current = p.absolute(dir);
    for (var i = 0; i < 8; i++) {
      out.add(current);
      final parent = p.dirname(current);
      if (parent == current) break;
      current = parent;
    }
    return out;
  }

  static String _resolve(String raw, List<String> roots, String fallbackDir) {
    final normalized = p.posix.normalize(raw.replaceAll(r'\', '/'));
    if (p.isAbsolute(normalized)) return p.normalize(normalized);
    for (final root in roots) {
      final candidate = p.normalize(p.join(root, normalized));
      if (File(candidate).existsSync()) return candidate;
    }
    for (final root in roots) {
      if (File(p.join(root, 'pubspec.yaml')).existsSync()) {
        return p.normalize(p.join(root, normalized));
      }
    }
    return p.normalize(p.join(fallbackDir, normalized));
  }
}
