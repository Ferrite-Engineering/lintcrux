// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:lintcrux/services/rohd/rohd_sidecar.dart';
import 'package:lintcrux/services/rohd/rohd_source_index.dart';
import 'package:path/path.dart' as p;

/// What [loadRohdSourceMaps] found.
class RohdSourceMaps {
  /// Creates a result.
  const RohdSourceMaps({required this.byFile, required this.warnings});

  /// No source maps and nothing to say.
  static const RohdSourceMaps none = RohdSourceMaps(
    byFile: <String, RohdFileIndex>{},
    warnings: <String>[],
  );

  /// An index per linted SystemVerilog file that has one, keyed by the
  /// normalized absolute path.
  final Map<String, RohdFileIndex> byFile;

  /// Sentences to show the user: a sidecar that was found and not used, and
  /// why. Never an error; the lint run is unaffected.
  final List<String> warnings;
}

/// The `perEngineOptions` key a project uses to say where sidecars are.
const String kRohdOptionsKey = 'rohd';

/// The option under [kRohdOptionsKey]: a path, or a list of paths, to
/// `.flc.json` sidecars or to directories holding them. Relative paths are
/// against the project root.
const String kRohdSidecarOption = 'sidecar';

/// Reads the ROHD source-trace data for the SystemVerilog files in
/// [sourceFiles].
///
/// For each `.sv` file the sidecars considered are, in this order, the ones
/// the project names under `perEngineOptions.rohd.sidecar` and every
/// `*.flc.json` in the file's own directory. A sidecar applies to a file it
/// describes (see [RohdFileIndex]). A file with no sidecar still gets an index
/// when its text carries `// ROHD:` comments.
///
/// **Never throws, never fails the run.** An unreadable file, a sidecar that is
/// not JSON and a sidecar of a version this reader does not know each become a
/// warning (once per sidecar) and are left out.
Future<RohdSourceMaps> loadRohdSourceMaps({
  required Iterable<String> sourceFiles,
  required String projectRoot,
  Map<String, Object?> options = const <String, Object?>{},
}) async {
  final svFiles = <String>[
    for (final f in sourceFiles)
      if (f.toLowerCase().endsWith('.sv')) p.normalize(p.absolute(f)),
  ];
  if (svFiles.isEmpty) return RohdSourceMaps.none;

  final configured = <String>[
    for (final entry in _configuredPaths(options))
      p.normalize(
        p.isAbsolute(entry) ? entry : p.join(projectRoot, entry),
      ),
  ];

  final warnings = <String>[];
  final parsed = <String, RohdSidecar?>{};
  final byFile = <String, RohdFileIndex>{};

  Future<RohdSidecar?> read(String path, {required bool warn}) async {
    if (parsed.containsKey(path)) return parsed[path];
    RohdSidecar? sidecar;
    try {
      final result = parseRohdSidecar(await File(path).readAsString());
      sidecar = result.sidecar;
      if (sidecar == null && warn) {
        warnings.add(
          'The ROHD source-trace file $path was not used: ${result.problem}.',
        );
      }
    } on Object {
      if (warn) {
        warnings.add('The ROHD source-trace file $path could not be read.');
      }
    }
    return parsed[path] = sidecar;
  }

  for (final sv in svFiles) {
    List<String> lines;
    try {
      lines = await File(sv).readAsLines();
    } on Object {
      continue;
    }
    final dir = p.dirname(sv);
    final stem = p.basenameWithoutExtension(sv).toLowerCase();

    final candidates = <(String, bool)>[
      for (final c in await _expand(configured)) (c, true),
      for (final c in await _flcIn(dir))
        (
          c,
          // A sidecar named for this file is expected to be good; a stranger
          // in the directory is only used if it happens to describe the file.
          p.basename(c).toLowerCase() == '$stem.flc.json',
        ),
    ];
    final sidecars = <RohdSidecar>[];
    final dirs = <String>[];
    final seen = <String>{};
    for (final (path, warn) in candidates) {
      if (!seen.add(path)) continue;
      final sidecar = await read(path, warn: warn);
      if (sidecar == null) continue;
      sidecars.add(sidecar);
      dirs.add(p.dirname(path));
    }

    final index = RohdFileIndex.build(
      svPath: sv,
      lines: lines,
      sidecars: sidecars,
      sidecarDirs: dirs,
    );
    if (!index.isEmpty) byFile[sv] = index;
  }

  return RohdSourceMaps(
    byFile: Map<String, RohdFileIndex>.unmodifiable(byFile),
    warnings: List<String>.unmodifiable(warnings),
  );
}

List<String> _configuredPaths(Map<String, Object?> options) {
  final value = options[kRohdSidecarOption];
  if (value is String && value.isNotEmpty) return <String>[value];
  if (value is List<Object?>) {
    return <String>[
      for (final v in value)
        if (v is String && v.isNotEmpty) v,
    ];
  }
  return const <String>[];
}

/// Files stay as they are; a directory becomes its `*.flc.json`.
Future<List<String>> _expand(List<String> paths) async {
  final out = <String>[];
  for (final path in paths) {
    try {
      if (FileSystemEntity.isDirectorySync(path)) {
        out.addAll(await _flcIn(path));
      } else {
        out.add(path);
      }
    } on Object {
      out.add(path);
    }
  }
  return out;
}

Future<List<String>> _flcIn(String dir) async {
  try {
    final names = <String>[
      await for (final e in Directory(dir).list(followLinks: false))
        if (e is File && e.path.toLowerCase().endsWith('.flc.json')) e.path,
    ]..sort();
    return names;
  } on Object {
    return const <String>[];
  }
}
