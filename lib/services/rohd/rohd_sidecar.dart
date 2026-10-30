// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Reader for the source-trace sidecar ROHD writes beside generated
/// SystemVerilog: `<Top>.flc.json`, "FLC" for file, line, column.
///
/// ROHD 0.7 or later writes it when `SourceTracer.activate()` ran before the
/// design was built and `TraceService(...).write(dir)` ran after. This reader
/// understands **version 6**, the version of the first ROHD release that has
/// it. Any other version is refused with a message and the lint run goes on
/// without the mapping; it never fails the run.
///
/// ```json
/// {
///   "version": 6,
///   "files": [".dart_tool/../lib/design.dart"],
///   "packageRoot": "/work/rohd_fixture",
///   "modules": {
///     "Top": {
///       "outputFiles": {"sv": ["/work/rohd_fixture/./Top.sv"]},
///       "tree": [
///         ["0:59:19", "gated@sv:51:1;sv:54:7;sv:43:13"],
///         ["0:58:19", ["0:24:15", "sum@sv:61:40;sv:46:13"],
///                     ["0:21:29", "*adder@61:8"]]
///       ]
///     }
///   }
/// }
/// ```
///
/// A `tree` is a trie of Dart frames, outermost frame first, and its leaves
/// are symbols. A leaf reads `[*]name[@pos[;pos...]][~original]`:
///
/// - `*` marks a submodule instance or a block (`*adder`, `*combinational`).
/// - each `pos` is `sv:LINE:COL`, a position in the generated SystemVerilog.
///   Older writers used a bare `LINE:COL` for a single position. `sc:` is
///   SystemC and is not read here.
/// - `~original` is the Dart name before SystemVerilog renaming.
///
/// A frame is `fileIndex:line:column`, an index into `files`.
///
/// **Never throws.** Wrong types and unknown shapes are skipped.
library;

import 'dart:convert';

import 'package:meta/meta.dart';

/// A Dart frame: `fileIndex:line:column`.
@immutable
class RohdFrame {
  /// Creates a frame.
  const RohdFrame(this.fileIndex, this.line, this.column);

  /// Parses `0:26:18` (or `0:26`), or returns `null`.
  static RohdFrame? parse(String text) {
    final parts = text.split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    final file = int.tryParse(parts[0]);
    final line = int.tryParse(parts[1]);
    final column = parts.length == 3 ? int.tryParse(parts[2]) : 1;
    if (file == null || line == null || column == null) return null;
    if (file < 0 || line < 1 || column < 1) return null;
    return RohdFrame(file, line, column);
  }

  /// Index into the sidecar's `files`.
  final int fileIndex;

  /// 1-based line.
  final int line;

  /// 1-based column.
  final int column;

  @override
  bool operator ==(Object other) =>
      other is RohdFrame &&
      other.fileIndex == fileIndex &&
      other.line == line &&
      other.column == column;

  @override
  int get hashCode => Object.hash(fileIndex, line, column);

  @override
  String toString() => '$fileIndex:$line:$column';
}

/// A position in the generated SystemVerilog.
class RohdSvPosition {
  /// Creates a position.
  const RohdSvPosition(this.line, this.column);

  /// 1-based line.
  final int line;

  /// 1-based column.
  final int column;
}

/// One traced name in a generated module.
class RohdSymbol {
  /// Creates a symbol.
  const RohdSymbol({
    required this.name,
    required this.isInstance,
    required this.positions,
    required this.frames,
    this.original,
  });

  /// The SystemVerilog name.
  final String name;

  /// The Dart name before renaming (`~data`), when it differs.
  final String? original;

  /// Whether this is a submodule instance or a block, not a signal.
  final bool isInstance;

  /// Every generated-SystemVerilog position of this name: its declaration,
  /// the assignments that drive it, its port connections.
  final List<RohdSvPosition> positions;

  /// The Dart frames that created it, **outermost first** as the tree stores
  /// them. The last is the innermost: the line that made the signal.
  final List<RohdFrame> frames;
}

/// One generated module.
class RohdModule {
  /// Creates a module.
  const RohdModule({
    required this.name,
    required this.svFileNames,
    required this.symbols,
  });

  /// The module's key in the sidecar.
  final String name;

  /// Base names of the SystemVerilog files this module was written to. Empty
  /// for the modules ROHD synthesizes inline (adders, flops, sequential
  /// blocks) that have no file of their own.
  final List<String> svFileNames;

  /// Every symbol, in tree order.
  final List<RohdSymbol> symbols;
}

/// A parsed sidecar.
class RohdSidecar {
  /// Creates a sidecar.
  const RohdSidecar({
    required this.files,
    required this.modules,
    this.packageRoot,
  });

  /// The only version this reader understands.
  static const int supportedVersion = 6;

  /// The Dart files frames refer to, as written (`.dart_tool/../lib/x.dart`).
  final List<String> files;

  /// The generated modules.
  final List<RohdModule> modules;

  /// The absolute package root on the machine that generated it, when
  /// recorded.
  final String? packageRoot;
}

/// The result of reading a sidecar: the sidecar, or why there is none.
class RohdSidecarResult {
  const RohdSidecarResult._(this.sidecar, this.problem);

  /// A readable sidecar.
  const RohdSidecarResult.ok(RohdSidecar sidecar) : this._(sidecar, null);

  /// A sidecar that cannot be used, with a sentence saying why.
  const RohdSidecarResult.unusable(String problem) : this._(null, problem);

  /// The sidecar, or `null`.
  final RohdSidecar? sidecar;

  /// Why [sidecar] is null.
  final String? problem;
}

/// Parses sidecar [text].
RohdSidecarResult parseRohdSidecar(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return const RohdSidecarResult.unusable('it is not valid JSON');
  }
  if (decoded is! Map<String, Object?>) {
    return const RohdSidecarResult.unusable('it is not a JSON object');
  }
  final version = decoded['version'];
  if (version != RohdSidecar.supportedVersion) {
    return RohdSidecarResult.unusable(
      version is int
          ? 'it is version $version and LintCrux reads version '
                '${RohdSidecar.supportedVersion}'
          : 'it has no version number and LintCrux reads version '
                '${RohdSidecar.supportedVersion}',
    );
  }
  final filesRaw = decoded['files'];
  final files = <String>[
    if (filesRaw is List<Object?>)
      for (final f in filesRaw)
        if (f is String) f,
  ];
  final modules = <RohdModule>[];
  final modulesRaw = decoded['modules'];
  if (modulesRaw is Map<String, Object?>) {
    for (final entry in modulesRaw.entries) {
      final module = entry.value;
      if (module is! Map<String, Object?>) continue;
      modules.add(
        RohdModule(
          name: entry.key,
          svFileNames: _svFileNames(module['outputFiles']),
          symbols: _symbols(module['tree']),
        ),
      );
    }
  }
  final root = decoded['packageRoot'];
  return RohdSidecarResult.ok(
    RohdSidecar(
      files: files,
      modules: modules,
      packageRoot: root is String && root.isNotEmpty ? root : null,
    ),
  );
}

List<String> _svFileNames(Object? outputFiles) {
  if (outputFiles is! Map<String, Object?>) return const <String>[];
  final sv = outputFiles['sv'];
  if (sv is! List<Object?>) return const <String>[];
  return <String>[
    for (final f in sv)
      if (f is String && f.isNotEmpty) f.split(RegExp(r'[\\/]')).last,
  ];
}

const int _maxDepth = 64;

List<RohdSymbol> _symbols(Object? tree) {
  final out = <RohdSymbol>[];
  if (tree is List<Object?>) {
    for (final node in tree) {
      _walk(node, const <RohdFrame>[], out, 0);
    }
  }
  return out;
}

void _walk(
  Object? node,
  List<RohdFrame> outer,
  List<RohdSymbol> out,
  int depth,
) {
  if (node is! List<Object?> || node.isEmpty || depth > _maxDepth) return;
  final head = node.first;
  if (head is! String) return;
  final frame = RohdFrame.parse(head);
  if (frame == null) return;
  final frames = <RohdFrame>[...outer, frame];
  for (final child in node.skip(1)) {
    if (child is String) {
      final symbol = _leaf(child, frames);
      if (symbol != null) out.add(symbol);
    } else {
      _walk(child, frames, out, depth + 1);
    }
  }
}

RohdSymbol? _leaf(String text, List<RohdFrame> frames) {
  var body = text;
  final isInstance = body.startsWith('*');
  if (isInstance) body = body.substring(1);
  String? original;
  final tilde = body.indexOf('~');
  if (tilde >= 0) {
    original = body.substring(tilde + 1);
    body = body.substring(0, tilde);
    if (original.isEmpty) original = null;
  }
  var name = body;
  final positions = <RohdSvPosition>[];
  final at = body.indexOf('@');
  if (at >= 0) {
    name = body.substring(0, at);
    for (final raw in body.substring(at + 1).split(';')) {
      final position = _position(raw);
      if (position != null) positions.add(position);
    }
  }
  if (name.isEmpty) return null;
  return RohdSymbol(
    name: name,
    original: original,
    isInstance: isInstance,
    positions: positions,
    frames: frames,
  );
}

/// `sv:LINE:COL`, or the older bare `LINE:COL`. `sc:` is SystemC: not read.
RohdSvPosition? _position(String raw) {
  var text = raw;
  if (text.startsWith('sv:')) {
    text = text.substring(3);
  } else if (text.contains(RegExp('^[A-Za-z]'))) {
    return null;
  }
  final parts = text.split(':');
  if (parts.length != 2) return null;
  final line = int.tryParse(parts[0]);
  final column = int.tryParse(parts[1]);
  if (line == null || line < 1 || column == null || column < 1) return null;
  return RohdSvPosition(line, column);
}
