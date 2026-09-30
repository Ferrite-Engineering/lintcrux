// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:path/path.dart' as p;

/// Applies a partial `.lintcrux` document over a loaded [LintProject] —
/// the `--config <path>` flag.
///
/// The overlay is a JSON object using the same key names as a
/// `.lintcrux` project file, but every key is optional. Keys that are
/// present replace the corresponding project field wholesale; keys that
/// are absent leave the project untouched. `name` and `rootPath` are
/// deliberately **not** overlayable — they identify the project, and a
/// CI overlay that silently re-rooted the source list would be a
/// footgun.
///
/// The point is a CI job tuning a committed project without editing it
/// in-tree:
///
/// ```json
/// {
///   "enabledEngineIds": ["verilator"],
///   "defines": { "SYNTHESIS": "1" },
///   "severityOverrides": { "verilator/UNUSEDSIGNAL": "note" }
/// }
/// ```
///
/// Relative paths inside the overlay resolve against the overlay file's
/// own directory, matching how `HeadlessInputResolver` treats the
/// project file.
///
/// ### Why JSON and not YAML
///
/// `.lintcrux` project files have always been JSON
/// (see [ProjectFileCodec]); the `--config` help text used to say
/// "YAML", which was never true of anything that shipped. Rather than
/// take a YAML dependency to make a stale sentence correct, the overlay
/// speaks the format the rest of the product already speaks.
class ProjectConfigOverlay {
  /// Creates a [ProjectConfigOverlay].
  const ProjectConfigOverlay();

  /// Reads the overlay at [overlayPath] and applies it to [project].
  ///
  /// Throws [ProjectConfigOverlayException] when the file is missing,
  /// is not a JSON object, or carries a value of the wrong shape. A
  /// malformed overlay must fail the run rather than be ignored — a CI
  /// job whose severity overrides silently did not apply reports the
  /// wrong answer.
  Future<LintProject> applyFile(
    LintProject project,
    String overlayPath,
  ) async {
    final abs = p.normalize(p.absolute(overlayPath));
    final file = File(abs);
    if (!file.existsSync()) {
      throw ProjectConfigOverlayException('config file not found: $abs');
    }
    final String raw;
    try {
      raw = await file.readAsString();
    } on FileSystemException catch (e) {
      throw ProjectConfigOverlayException(
        'could not read config file $abs: ${e.message}',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      throw ProjectConfigOverlayException(
        'config file $abs is not valid JSON: ${e.message}',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw ProjectConfigOverlayException(
        'config file $abs must contain a JSON object, got '
        '${decoded.runtimeType}',
      );
    }
    return apply(project, decoded, base: p.dirname(abs));
  }

  /// Applies an already-decoded [overlay] map to [project]. [base] is
  /// the directory relative paths in the overlay resolve against.
  LintProject apply(
    LintProject project,
    Map<String, dynamic> overlay, {
    required String base,
  }) {
    final unknown = overlay.keys.where((k) => !_overlayableKeys.contains(k));
    if (unknown.isNotEmpty) {
      throw ProjectConfigOverlayException(
        'unsupported config key(s): ${unknown.join(', ')}. '
        'Overlayable keys: ${_overlayableKeys.join(', ')}.',
      );
    }

    var out = project;

    if (overlay.containsKey('sourceFiles')) {
      out = out.copyWith(
        sourceFiles: _stringList(
          overlay['sourceFiles'],
          'sourceFiles',
        ).map((f) => _abs(base, f)).toList(growable: false),
      );
    }
    if (overlay.containsKey('includePaths')) {
      out = out.copyWith(
        includePaths: _stringList(
          overlay['includePaths'],
          'includePaths',
        ).map((d) => _abs(base, d)).toList(growable: false),
      );
    }
    if (overlay.containsKey('defines')) {
      out = out.copyWith(defines: _stringMap(overlay['defines'], 'defines'));
    }
    if (overlay.containsKey('topModule')) {
      final v = overlay['topModule'];
      if (v is! String) {
        throw const ProjectConfigOverlayException(
          '"topModule" must be a string',
        );
      }
      out = out.copyWith(topModule: v);
    }
    if (overlay.containsKey('language')) {
      out = out.copyWith(language: _language(overlay['language']));
    }
    if (overlay.containsKey('enabledEngineIds')) {
      out = out.copyWith(
        enabledEngineIds: _stringList(
          overlay['enabledEngineIds'],
          'enabledEngineIds',
        ),
      );
    }
    if (overlay.containsKey('severityOverrides')) {
      out = out.copyWith(
        severityOverrides: _severities(overlay['severityOverrides']),
      );
    }
    if (overlay.containsKey('perEngineOptions')) {
      final v = overlay['perEngineOptions'];
      if (v is! Map<String, dynamic>) {
        throw const ProjectConfigOverlayException(
          '"perEngineOptions" must be an object',
        );
      }
      out = out.copyWith(
        perEngineOptions: <String, Map<String, Object?>>{
          for (final entry in v.entries)
            entry.key: entry.value is Map<String, dynamic>
                ? Map<String, Object?>.from(entry.value as Map<String, dynamic>)
                : throw ProjectConfigOverlayException(
                    '"perEngineOptions.${entry.key}" must be an object',
                  ),
        },
      );
    }

    return out;
  }

  /// Keys the overlay understands. `name` / `rootPath` are excluded on
  /// purpose (see the class doc); `filterPresets`, `sourceFileLanguages`
  /// and `customRegexRules` are excluded because they are editor-owned
  /// state with no CI use.
  static const Set<String> _overlayableKeys = <String>{
    'sourceFiles',
    'includePaths',
    'defines',
    'topModule',
    'language',
    'enabledEngineIds',
    'severityOverrides',
    'perEngineOptions',
  };

  static String _abs(String base, String path) =>
      p.isAbsolute(path) ? p.normalize(path) : p.normalize(p.join(base, path));

  static List<String> _stringList(Object? value, String key) {
    if (value is! List) {
      throw ProjectConfigOverlayException('"$key" must be an array of strings');
    }
    return <String>[
      for (final e in value)
        if (e is String)
          e
        else
          throw ProjectConfigOverlayException(
            '"$key" must contain only strings; got ${e.runtimeType}',
          ),
    ];
  }

  static Map<String, String> _stringMap(Object? value, String key) {
    if (value is! Map<String, dynamic>) {
      throw ProjectConfigOverlayException('"$key" must be an object');
    }
    return <String, String>{
      for (final entry in value.entries)
        entry.key: entry.value is String
            ? entry.value as String
            : '${entry.value}',
    };
  }

  static HdlLanguage _language(Object? value) {
    if (value is! String) {
      throw const ProjectConfigOverlayException(
        '"language" must be a string',
      );
    }
    final normalized = value.toLowerCase().replaceAll(RegExp('[-_ ]'), '');
    for (final lang in HdlLanguage.values) {
      if (lang.name.toLowerCase() == normalized) return lang;
    }
    throw ProjectConfigOverlayException(
      'unknown language "$value"; expected one of '
      '${HdlLanguage.values.map((l) => l.name).join(', ')}',
    );
  }

  static Map<String, Severity> _severities(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const ProjectConfigOverlayException(
        '"severityOverrides" must be an object',
      );
    }
    return <String, Severity>{
      for (final entry in value.entries)
        entry.key: Severity.values.firstWhere(
          (s) => s.name == '${entry.value}',
          orElse: () => throw ProjectConfigOverlayException(
            'unknown severity "${entry.value}" for rule "${entry.key}"; '
            'expected one of ${Severity.values.map((s) => s.name).join(', ')}',
          ),
        ),
    };
  }
}

/// Thrown when a `--config` overlay cannot be read or understood.
class ProjectConfigOverlayException implements Exception {
  /// Creates a [ProjectConfigOverlayException] with [message].
  const ProjectConfigOverlayException(this.message);

  /// Human-readable explanation, printable to stderr verbatim.
  final String message;

  @override
  String toString() => 'config overlay error: $message';
}
