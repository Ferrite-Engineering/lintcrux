// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';

/// Pure-Dart fingerprint helpers for the lint-run cache.
///
/// Fingerprints are SHA-256 hex digests. Two rules apply uniformly:
///
/// 1. **Determinism.** The same source bytes and the same config
///    must produce the same fingerprint on every machine and every
///    locale. JSON serialization sorts map keys; line endings are
///    normalized to LF before hashing the source.
///
/// 2. **No environment leakage.** The config fingerprint includes
///    only fields that affect the engine's output — engine binary
///    path, engine options, include paths, defines, top module,
///    project-level severity overrides, and the contents of the engine's
///    own configuration file ([configFilesOf]). It deliberately does *not*
///    include user-environment knobs (`PATH`, `HOME`,
///    `LINTCRUX_DEBUG`) that would otherwise spuriously invalidate
///    the cache across runs on the same machine.
class CacheFingerprint {
  CacheFingerprint._();

  /// Computes the source fingerprint for [filePath]. Reads the file
  /// from disk, normalizes line endings to LF (so CRLF ↔ LF
  /// checkout flips do not invalidate the cache), and returns the
  /// SHA-256 hex digest.
  ///
  /// Returns `null` when the file does not exist or cannot be read
  /// (the caller treats a `null` fingerprint as a cache miss and
  /// re-invokes the engine, which will surface a fresh I/O error
  /// via its normal error reporting path).
  static Future<String?> sourceOf(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      return _sourceHashFromBytes(bytes);
    } on FileSystemException {
      return null;
    }
  }

  /// Computes the source fingerprint for an in-memory byte buffer.
  /// Exposed so tests don't need to hit the file system; the runner
  /// always uses the file-based variants.
  static String sourceOfBytes(List<int> bytes) => _sourceHashFromBytes(bytes);

  /// Computes the config fingerprint for the engine invocation
  /// described by [request].
  ///
  /// Canonicalization rules:
  ///   * Maps emitted with sorted keys (recursively).
  ///   * Lists preserved in their original order — `sourceFiles`
  ///     ordering is deliberate (matches the engine's invocation
  ///     order); `includePaths` ordering is engine-significant
  ///     (search path order).
  ///   * `null` values dropped from the engine-options bag to
  ///     keep canonical JSON minimal.
  ///   * The engine binary `path` is normalized via
  ///     `File(path).absolute.path` so a relative path with the
  ///     same target as an absolute path produces the same hash.
  ///   * `language` serialized as its enum name.
  ///   * `binary.source` serialized as its enum name.
  ///   * [engineId]'s configuration files ([configFilesOf]) contribute
  ///     their content hash, so editing one invalidates the entry.
  static String configOf(LintRunRequest request, {String engineId = ''}) {
    final configFiles = configFilesOf(engineId, request);
    final canonical = <String, Object?>{
      // Engine-input shape.
      'sourceFiles': request.sourceFiles,
      'includePaths': request.includePaths,
      'defines': _sortMap(request.defines),
      'topModule': request.topModule,
      'language': request.language.name,
      // Binary resolution.
      'binary': <String, Object?>{
        'source': request.binary.source.name,
        'path': _normalizePath(request.binary.path),
      },
      // Engine-specific options bag.
      'options': _sortValue(request.options),
      // Configuration files the engine reads that are not sources. Absent
      // for an engine with none, so their keys are unchanged.
      if (configFiles.isNotEmpty)
        'configFiles': <String, Object?>{
          for (final path in configFiles) path: _contentHashOf(path),
        },
    };
    return _hashJson(canonical);
  }

  /// The configuration files [engineId] reads for [request] that are not in
  /// `sourceFiles`, in the order the engine consults them.
  ///
  /// The cache key must see them: a key blind to a config file replays the
  /// result from before the user edited it, and the edit appears to do
  /// nothing. Verible reads `.rules.verible_lint` from the project root;
  /// Svlint reads the `configPath` option, else `.svlint.toml` in the
  /// project root. A file that does not exist is still listed — its absence
  /// hashes differently from any content, so creating it invalidates too.
  static List<String> configFilesOf(String engineId, LintRunRequest request) {
    final root = request.projectRoot;
    String inRoot(String name) =>
        root.isEmpty ? '' : (root.endsWith('/') ? '$root$name' : '$root/$name');
    switch (engineId) {
      case 'verible':
        return <String>[
          if (root.isNotEmpty) inRoot('.rules.verible_lint'),
        ];
      case 'svlint':
        final explicit = request.options['configPath'];
        if (explicit is String && explicit.isNotEmpty) {
          return <String>[explicit];
        }
        return <String>[if (root.isNotEmpty) inRoot('.svlint.toml')];
      default:
        return const <String>[];
    }
  }

  static String? _contentHashOf(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      return _sourceHashFromBytes(file.readAsBytesSync());
    } on FileSystemException {
      return null;
    }
  }

  static String _sourceHashFromBytes(List<int> bytes) {
    // Normalize line endings: CR (0x0D) → drop, so CRLF becomes LF
    // and bare CR (rare) becomes nothing. Cheap byte-level filter,
    // no string allocation for the common ASCII source case.
    final normalized = List<int>.filled(bytes.length, 0);
    var w = 0;
    for (final b in bytes) {
      if (b == 0x0D) continue;
      normalized[w++] = b;
    }
    final view = w == bytes.length ? normalized : normalized.sublist(0, w);
    return sha256.convert(view).toString();
  }

  static String _hashJson(Object? canonical) {
    final encoded = utf8.encode(jsonEncode(canonical));
    return sha256.convert(encoded).toString();
  }

  static Map<String, Object?> _sortMap(Map<String, Object?> map) {
    final keys = map.keys.toList()..sort();
    return <String, Object?>{
      for (final k in keys) k: _sortValue(map[k]),
    };
  }

  static Object? _sortValue(Object? value) {
    if (value == null) return null;
    if (value is Map<String, Object?>) {
      final keys = value.keys.toList()..sort();
      return <String, Object?>{
        for (final k in keys)
          if (value[k] != null) k: _sortValue(value[k]),
      };
    }
    if (value is Map) {
      // Non-String-keyed map: coerce keys to String, sort, recurse.
      final entries =
          value.entries.map((e) => MapEntry(e.key.toString(), e.value)).toList()
            ..sort((a, b) => a.key.compareTo(b.key));
      return <String, Object?>{
        for (final e in entries)
          if (e.value != null) e.key: _sortValue(e.value as Object?),
      };
    }
    if (value is Iterable) {
      return value.map(_sortValue).toList(growable: false);
    }
    return value;
  }

  static String _normalizePath(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      return File(raw).absolute.path;
    } on Object {
      return raw;
    }
  }
}
