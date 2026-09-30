// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/custom_regex_rule.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/named_filter_preset.dart';
import 'package:lintcrux/domain/models/project_source_file.dart';

/// The current `.lintcrux` schema version. Bump whenever a
/// backwards-incompatible change lands; forward-compatible additions
/// (new optional fields) do not require a bump because
/// [ProjectFileCodec] silently ignores unknown keys.
const int kProjectFileSchemaVersion = 1;

/// Encode / decode `.lintcrux` JSON project files.
///
/// `.lintcrux` is a flat JSON object whose top level carries a `version`
/// integer (current = [kProjectFileSchemaVersion]). The codec rejects
/// unknown major versions with a clear [ProjectFileException], silently
/// ignores unknown fields for forward compatibility, and treats every
/// field as optional except `name` and `rootPath`.
///
/// The codec works at the JSON-string layer only — it does no
/// filesystem I/O. Callers wrap reads/writes around it with
/// `File.readAsString` / `File.writeAsString`. Keeping the codec
/// I/O-free makes it trivially testable and lets the same code path
/// serve the future web "drag a `.lintcrux` into the browser" upload
/// flow without dragging `dart:io` into the bundle.
class ProjectFileCodec {
  /// Creates a [ProjectFileCodec].
  const ProjectFileCodec();

  /// Encode [project] as pretty-printed JSON suitable for committing
  /// to a Git repo. Pretty-print is intentional: the file is meant to
  /// diff cleanly in code review.
  String encode(LintProject project) {
    final map = <String, Object?>{
      'version': kProjectFileSchemaVersion,
      'name': project.name,
      'rootPath': project.rootPath,
      'sourceFiles': List<String>.from(project.sourceFiles),
      'includePaths': List<String>.from(project.includePaths),
      'defines': Map<String, String>.from(project.defines),
      if (project.topModule != null) 'topModule': project.topModule,
      'language': _languageToString(project.language),
      'enabledEngineIds': List<String>.from(project.enabledEngineIds),
      'severityOverrides': <String, String>{
        for (final e in project.severityOverrides.entries)
          e.key: _severityToString(e.value),
      },
      'perEngineOptions': <String, Map<String, Object?>>{
        for (final e in project.perEngineOptions.entries)
          e.key: Map<String, Object?>.from(e.value),
      },
      'filterPresets': <Map<String, Object?>>[
        for (final p in project.filterPresets) p.toJson(),
      ],
      'sourceFileLanguages': <String, String>{
        for (final e in project.sourceFileLanguages.entries)
          e.key: _sourceFileLanguageToString(e.value),
      },
      'sourceFileProvenance': Map<String, String>.from(
        project.sourceFileProvenance,
      ),
      'customRegexRules': <Map<String, Object?>>[
        for (final r in project.customRegexRules)
          <String, Object?>{
            'id': r.id,
            'severity': _severityToString(r.severity),
            'pattern': r.pattern,
            'patternKind': _patternKindToString(r.patternKind),
            'messageTemplate': r.messageTemplate,
            if (r.filePathGlob != null) 'filePathGlob': r.filePathGlob,
            'enabled': r.enabled,
          },
      ],
    };
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(map);
  }

  /// Parse a `.lintcrux` JSON string into a [LintProject].
  ///
  /// Throws [ProjectFileException] for malformed JSON, missing required
  /// fields, or an unsupported `version`. Unknown keys at any level are
  /// silently ignored.
  LintProject decode(String jsonString) {
    final dynamic raw;
    try {
      raw = json.decode(jsonString);
    } on FormatException catch (e) {
      throw ProjectFileException('invalid JSON: ${e.message}', cause: e);
    }
    if (raw is! Map<String, dynamic>) {
      throw const ProjectFileException(
        'project file must be a JSON object at the top level',
      );
    }

    final version = raw['version'];
    if (version is! int) {
      throw const ProjectFileException(
        'missing or non-integer "version" field',
      );
    }
    if (version != kProjectFileSchemaVersion) {
      throw ProjectFileException(
        'unsupported schema version $version '
        '(this build understands version $kProjectFileSchemaVersion)',
      );
    }

    final name = raw['name'];
    if (name is! String || name.isEmpty) {
      throw const ProjectFileException(
        'missing or empty "name" field',
      );
    }
    final rootPath = raw['rootPath'];
    if (rootPath is! String || rootPath.isEmpty) {
      throw const ProjectFileException(
        'missing or empty "rootPath" field',
      );
    }

    final language = _languageFromString(
      _expectStringOrNull(raw, 'language'),
    );
    return LintProject(
      name: name,
      rootPath: rootPath,
      sourceFiles: _stringList(raw, 'sourceFiles'),
      includePaths: _stringList(raw, 'includePaths'),
      defines: _stringMap(raw, 'defines'),
      topModule: _expectStringOrNull(raw, 'topModule'),
      language: language,
      enabledEngineIds: _stringList(raw, 'enabledEngineIds'),
      severityOverrides: _severityMap(raw, 'severityOverrides'),
      perEngineOptions: _nestedOptionsMap(raw, 'perEngineOptions'),
      filterPresets: _filterPresetList(raw, 'filterPresets'),
      sourceFileLanguages: _sourceFileLanguageMap(raw, 'sourceFileLanguages'),
      customRegexRules: _customRegexRuleList(raw, 'customRegexRules'),
      sourceFileProvenance: _stringMap(raw, 'sourceFileProvenance'),
    );
  }

  static String _patternKindToString(CustomRulePatternKind kind) {
    switch (kind) {
      case CustomRulePatternKind.sourceText:
        return 'source_text';
      case CustomRulePatternKind.signalName:
        return 'signal_name';
      case CustomRulePatternKind.identifier:
        return 'identifier';
    }
  }

  static CustomRulePatternKind _patternKindFromString(String? s) {
    switch (s) {
      case null:
      case 'source_text':
        return CustomRulePatternKind.sourceText;
      case 'signal_name':
        return CustomRulePatternKind.signalName;
      case 'identifier':
        return CustomRulePatternKind.identifier;
      default:
        throw ProjectFileException(
          'unknown customRegexRules pattern kind "$s"',
        );
    }
  }

  static List<CustomRegexRule> _customRegexRuleList(
    Map<String, dynamic> m,
    String key,
  ) {
    final v = m[key];
    if (v == null) return const <CustomRegexRule>[];
    if (v is! List) {
      throw ProjectFileException('"$key" must be a JSON array');
    }
    final out = <CustomRegexRule>[];
    for (final entry in v) {
      if (entry is! Map) {
        throw ProjectFileException(
          '"$key" must contain only JSON objects',
        );
      }
      final raw = Map<String, Object?>.from(entry);
      final id = raw['id'];
      if (id is! String || id.isEmpty) {
        throw ProjectFileException(
          '"$key" entry missing or empty "id"',
        );
      }
      final pattern = raw['pattern'];
      if (pattern is! String || pattern.isEmpty) {
        throw ProjectFileException(
          '"$key" entry "$id" missing or empty "pattern"',
        );
      }
      final messageTemplate = raw['messageTemplate'];
      if (messageTemplate is! String || messageTemplate.isEmpty) {
        throw ProjectFileException(
          '"$key" entry "$id" missing or empty "messageTemplate"',
        );
      }
      final severityRaw = raw['severity'];
      if (severityRaw is! String) {
        throw ProjectFileException(
          '"$key" entry "$id" missing "severity"',
        );
      }
      final patternKindRaw = raw['patternKind'];
      if (patternKindRaw != null && patternKindRaw is! String) {
        throw ProjectFileException(
          '"$key" entry "$id" "patternKind" must be a string',
        );
      }
      final filePathGlobRaw = raw['filePathGlob'];
      if (filePathGlobRaw != null && filePathGlobRaw is! String) {
        throw ProjectFileException(
          '"$key" entry "$id" "filePathGlob" must be a string',
        );
      }
      final enabledRaw = raw['enabled'];
      if (enabledRaw != null && enabledRaw is! bool) {
        throw ProjectFileException(
          '"$key" entry "$id" "enabled" must be a boolean',
        );
      }
      out.add(
        CustomRegexRule(
          id: id,
          severity: _severityFromString(severityRaw),
          pattern: pattern,
          patternKind: _patternKindFromString(patternKindRaw as String?),
          messageTemplate: messageTemplate,
          filePathGlob: filePathGlobRaw as String?,
          enabled: (enabledRaw as bool?) ?? true,
        ),
      );
    }
    return out;
  }

  static String _sourceFileLanguageToString(ProjectSourceFileLanguage l) {
    switch (l) {
      case ProjectSourceFileLanguage.auto:
        return 'auto';
      case ProjectSourceFileLanguage.verilog:
        return 'verilog';
      case ProjectSourceFileLanguage.systemVerilog:
        return 'systemverilog';
      case ProjectSourceFileLanguage.vhdl:
        return 'vhdl';
    }
  }

  static ProjectSourceFileLanguage? _sourceFileLanguageFromString(
    String s,
  ) {
    switch (s) {
      case 'auto':
        return ProjectSourceFileLanguage.auto;
      case 'verilog':
        return ProjectSourceFileLanguage.verilog;
      case 'systemverilog':
        return ProjectSourceFileLanguage.systemVerilog;
      case 'vhdl':
        return ProjectSourceFileLanguage.vhdl;
      default:
        return null;
    }
  }

  static Map<String, ProjectSourceFileLanguage> _sourceFileLanguageMap(
    Map<String, dynamic> m,
    String key,
  ) {
    final v = m[key];
    if (v == null) return const {};
    if (v is! Map) {
      throw ProjectFileException('"$key" must be a JSON object');
    }
    final out = <String, ProjectSourceFileLanguage>{};
    v.forEach((k, val) {
      if (k is! String || val is! String) {
        throw ProjectFileException(
          '"$key" entries must be string -> string',
        );
      }
      final lang = _sourceFileLanguageFromString(val);
      if (lang == null) {
        throw ProjectFileException(
          '"$key" value "$val" is not a known language',
        );
      }
      out[k] = lang;
    });
    return out;
  }

  static List<NamedFilterPreset> _filterPresetList(
    Map<String, dynamic> m,
    String key,
  ) {
    final v = m[key];
    if (v == null) return const [];
    if (v is! List) {
      throw ProjectFileException('"$key" must be a JSON array');
    }
    final out = <NamedFilterPreset>[];
    for (final entry in v) {
      if (entry is! Map) {
        throw ProjectFileException(
          '"$key" must contain only JSON objects',
        );
      }
      final preset = NamedFilterPreset.fromJson(
        Map<String, Object?>.from(entry),
      );
      // Silently drop entries that don't decode (missing/empty name).
      if (preset != null) out.add(preset);
    }
    return out;
  }

  // ─── helpers ─────────────────────────────────────────────────────────

  static List<String> _stringList(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v == null) return const [];
    if (v is! List) {
      throw ProjectFileException('"$key" must be a JSON array');
    }
    return v
        .map((e) {
          if (e is! String) {
            throw ProjectFileException(
              '"$key" must contain only strings (saw ${e.runtimeType})',
            );
          }
          return e;
        })
        .toList(growable: false);
  }

  static Map<String, String> _stringMap(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v == null) return const {};
    if (v is! Map) {
      throw ProjectFileException('"$key" must be a JSON object');
    }
    final out = <String, String>{};
    v.forEach((k, val) {
      if (k is! String || val is! String) {
        throw ProjectFileException(
          '"$key" entries must be string -> string',
        );
      }
      out[k] = val;
    });
    return out;
  }

  static Map<String, Severity> _severityMap(
    Map<String, dynamic> m,
    String key,
  ) {
    final v = m[key];
    if (v == null) return const {};
    if (v is! Map) {
      throw ProjectFileException('"$key" must be a JSON object');
    }
    final out = <String, Severity>{};
    v.forEach((k, val) {
      if (k is! String || val is! String) {
        throw ProjectFileException(
          '"$key" entries must be string -> string',
        );
      }
      out[k] = _severityFromString(val);
    });
    return out;
  }

  static Map<String, Map<String, Object?>> _nestedOptionsMap(
    Map<String, dynamic> m,
    String key,
  ) {
    final v = m[key];
    if (v == null) return const {};
    if (v is! Map) {
      throw ProjectFileException('"$key" must be a JSON object');
    }
    final out = <String, Map<String, Object?>>{};
    v.forEach((engineId, options) {
      if (engineId is! String) {
        throw ProjectFileException(
          '"$key" engine keys must be strings',
        );
      }
      if (options is! Map) {
        throw ProjectFileException(
          '"$key.$engineId" must be a JSON object',
        );
      }
      final bag = <String, Object?>{};
      options.forEach((k, val) {
        if (k is! String) {
          throw ProjectFileException(
            '"$key.$engineId" keys must be strings',
          );
        }
        bag[k] = val;
      });
      out[engineId] = bag;
    });
    return out;
  }

  static String? _expectStringOrNull(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v == null) return null;
    if (v is! String) {
      throw ProjectFileException('"$key" must be a string');
    }
    return v.isEmpty ? null : v;
  }

  static String _languageToString(HdlLanguage l) {
    switch (l) {
      case HdlLanguage.verilog:
        return 'verilog';
      case HdlLanguage.systemVerilog:
        return 'systemverilog';
      case HdlLanguage.vhdl:
        return 'vhdl';
      case HdlLanguage.mixed:
        return 'mixed';
    }
  }

  static HdlLanguage _languageFromString(String? s) {
    switch (s) {
      case null:
        return HdlLanguage.systemVerilog;
      case 'verilog':
        return HdlLanguage.verilog;
      case 'systemverilog':
        return HdlLanguage.systemVerilog;
      case 'vhdl':
        return HdlLanguage.vhdl;
      case 'mixed':
        return HdlLanguage.mixed;
      default:
        throw ProjectFileException('unknown language "$s"');
    }
  }

  static String _severityToString(Severity s) {
    switch (s) {
      case Severity.fatal:
        return 'fatal';
      case Severity.error:
        return 'error';
      case Severity.warning:
        return 'warning';
      case Severity.note:
        return 'note';
      case Severity.none:
        return 'none';
    }
  }

  static Severity _severityFromString(String s) {
    switch (s) {
      case 'fatal':
        return Severity.fatal;
      case 'error':
        return Severity.error;
      case 'warning':
        return Severity.warning;
      case 'note':
        return Severity.note;
      case 'none':
        return Severity.none;
      default:
        throw ProjectFileException('unknown severity "$s"');
    }
  }
}

/// Thrown by [ProjectFileCodec] for any malformed `.lintcrux` input.
///
/// Surfaced to the UI as a snackbar / error banner; the [message] is
/// English-only because the LintCrux locale system wraps error display
/// at the boundary.
class ProjectFileException implements Exception {
  /// Creates a [ProjectFileException].
  const ProjectFileException(this.message, {this.cause});

  /// English-only description of what went wrong.
  final String message;

  /// Optional underlying cause (typically a [FormatException]).
  final Object? cause;

  @override
  String toString() => 'ProjectFileException: $message';
}
