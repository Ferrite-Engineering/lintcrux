// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/custom_regex_rule.dart';
import 'package:lintcrux/domain/models/named_filter_preset.dart';
import 'package:lintcrux/domain/models/project_source_file.dart';
import 'package:meta/meta.dart';

/// A loaded LintCrux project — the in-memory form of a `.lintcrux` file.
///
/// The JSON parser and the `.lintcrux` schema versioning live in
/// `ProjectFileCodec`.
///
/// `enabledEngineIds` controls which engines run when the user hits
/// "Run All"; the per-engine binary configs are looked up out-of-band
/// via the `EngineRegistry`. `severityOverrides` maps namespaced rule
/// IDs (`"verilator/UNUSEDSIGNAL"`) to user-chosen severities for this
/// project; the override is applied at violation-construction time so
/// the [Violation.severity] field always reflects the post-override
/// value.
@immutable
class LintProject {
  /// Creates a [LintProject]. `name` and `rootPath` are required;
  /// everything else has a sensible empty default.
  const LintProject({
    required this.name,
    required this.rootPath,
    this.sourceFiles = const <String>[],
    this.includePaths = const <String>[],
    this.defines = const <String, String>{},
    this.topModule,
    this.language = HdlLanguage.systemVerilog,
    this.enabledEngineIds = const <String>[],
    this.severityOverrides = const <String, Severity>{},
    this.perEngineOptions = const <String, Map<String, Object?>>{},
    this.filterPresets = const <NamedFilterPreset>[],
    this.sourceFileLanguages = const <String, ProjectSourceFileLanguage>{},
    this.customRegexRules = const <CustomRegexRule>[],
    this.sourceFileProvenance = const <String, String>{},
  });

  /// Human-readable project name. Surfaced in the title bar and the
  /// recent-projects list.
  final String name;

  /// Absolute path to the project root. Relative paths in `.lintcrux`
  /// resolve against this.
  final String rootPath;

  /// Source files passed to the engines. Order is preserved for
  /// engines that care (Verilog `define` resolution).
  final List<String> sourceFiles;

  /// `+incdir+`-style include paths.
  final List<String> includePaths;

  /// `+define+`-style preprocessor defines.
  final Map<String, String> defines;

  /// Optional top module / entity used by engines that benefit from
  /// elaboration ordering (`yosys hierarchy -top`, etc.).
  final String? topModule;

  /// Primary language of the project. `mixed` enables routing
  /// per-engine.
  final HdlLanguage language;

  /// IDs of engines enabled for this project (e.g.
  /// `['verilator', 'verible', 'slang']`). Empty == "run all
  /// registered engines that support [language]".
  final List<String> enabledEngineIds;

  /// Per-rule severity overrides, keyed by engine-namespaced rule ID.
  /// Applied at violation parse time.
  final Map<String, Severity> severityOverrides;

  /// Per-engine options bag, keyed by engine id (`"verilator"`,
  /// `"verible"`, …). Values are passed through to the matching
  /// [LintEngine] as `LintRunRequest.options`. Untyped on purpose:
  /// each engine documents its own option keys.
  final Map<String, Map<String, Object?>> perEngineOptions;

  /// Per-project saved filter presets. Committed alongside source
  /// listings so a team shares the same preset names. The user-wide
  /// preset list (when it lands in `AppSettings`) merges with this
  /// list at runtime; per-project entries win on name collision.
  final List<NamedFilterPreset> filterPresets;

  /// Per-source-file language declaration map.
  ///
  /// Keys are entries from [sourceFiles]; values are explicit language
  /// declarations. Missing keys (or keys with [ProjectSourceFileLanguage.auto])
  /// fall back to extension-based detection — see
  /// [ProjectSourceFile.resolveLanguage], which the engine router
  /// applies. Older `.lintcrux` files load with the empty default
  /// unchanged.
  final Map<String, ProjectSourceFileLanguage> sourceFileLanguages;

  /// Project-scoped custom regex rules.
  ///
  /// Empty by default; the active `CustomRuleEvaluator` (Pro-tier
  /// implementation in the Pro overlay; no-op default in open-core)
  /// evaluates these alongside built-in engine rules and emits a
  /// violation per match. Backward-compatible: existing project files
  /// without `customRegexRules` decode to an empty list.
  final List<CustomRegexRule> customRegexRules;

  /// EDAM import — which external package/core contributed each source
  /// file, keyed by entries of [sourceFiles].
  ///
  /// Populated by the FuseSoC EDAM importer with the contributing
  /// core's VLNV (`vendor:library:name:version`); empty for projects
  /// from every other origin. Lets a violation surface separate "your
  /// code" from "a dependency". Missing keys mean "origin unknown /
  /// this project" — consumers must not treat absence as an error.
  final Map<String, String> sourceFileProvenance;

  /// Returns each entry of [sourceFiles] as a typed
  /// [ProjectSourceFile], applying the override in [sourceFileLanguages]
  /// when present. Used by the engine-routing layer.
  List<ProjectSourceFile> get sourceFilesTyped {
    return [
      for (final path in sourceFiles)
        ProjectSourceFile(
          path: path,
          language: sourceFileLanguages[path] ?? ProjectSourceFileLanguage.auto,
        ),
    ];
  }

  /// Returns a copy with overridden fields.
  LintProject copyWith({
    String? name,
    String? rootPath,
    List<String>? sourceFiles,
    List<String>? includePaths,
    Map<String, String>? defines,
    String? topModule,
    HdlLanguage? language,
    List<String>? enabledEngineIds,
    Map<String, Severity>? severityOverrides,
    Map<String, Map<String, Object?>>? perEngineOptions,
    List<NamedFilterPreset>? filterPresets,
    Map<String, ProjectSourceFileLanguage>? sourceFileLanguages,
    List<CustomRegexRule>? customRegexRules,
    Map<String, String>? sourceFileProvenance,
  }) {
    return LintProject(
      name: name ?? this.name,
      rootPath: rootPath ?? this.rootPath,
      sourceFiles: sourceFiles ?? this.sourceFiles,
      includePaths: includePaths ?? this.includePaths,
      defines: defines ?? this.defines,
      topModule: topModule ?? this.topModule,
      language: language ?? this.language,
      enabledEngineIds: enabledEngineIds ?? this.enabledEngineIds,
      severityOverrides: severityOverrides ?? this.severityOverrides,
      perEngineOptions: perEngineOptions ?? this.perEngineOptions,
      filterPresets: filterPresets ?? this.filterPresets,
      sourceFileLanguages: sourceFileLanguages ?? this.sourceFileLanguages,
      customRegexRules: customRegexRules ?? this.customRegexRules,
      sourceFileProvenance: sourceFileProvenance ?? this.sourceFileProvenance,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LintProject) return false;
    return other.name == name &&
        other.rootPath == rootPath &&
        _listEq(other.sourceFiles, sourceFiles) &&
        _listEq(other.includePaths, includePaths) &&
        _mapEq(other.defines, defines) &&
        other.topModule == topModule &&
        other.language == language &&
        _listEq(other.enabledEngineIds, enabledEngineIds) &&
        _mapEq(other.severityOverrides, severityOverrides) &&
        _nestedMapEq(other.perEngineOptions, perEngineOptions) &&
        _listEq(other.filterPresets, filterPresets) &&
        _mapEq(other.sourceFileLanguages, sourceFileLanguages) &&
        _listEq(other.customRegexRules, customRegexRules) &&
        _mapEq(other.sourceFileProvenance, sourceFileProvenance);
  }

  @override
  int get hashCode {
    // Map.entries does not have value-based equality, so hashing entries
    // directly produces order-dependent / instance-dependent results.
    // Stable map hash: combine sorted (key, value) pairs.
    int hashMap<K, V>(Map<K, V> m) {
      final keys = m.keys.toList()
        ..sort((a, b) => a.toString().compareTo(b.toString()));
      return Object.hashAll(keys.expand((k) => [k, m[k]]));
    }

    int hashNestedMap(Map<String, Map<String, Object?>> m) {
      final keys = m.keys.toList()..sort();
      return Object.hashAll(keys.expand((k) => [k, hashMap(m[k]!)]));
    }

    return Object.hash(
      name,
      rootPath,
      Object.hashAll(sourceFiles),
      Object.hashAll(includePaths),
      hashMap(defines),
      topModule,
      language,
      Object.hashAll(enabledEngineIds),
      hashMap(severityOverrides),
      hashNestedMap(perEngineOptions),
      Object.hashAll(filterPresets),
      hashMap(sourceFileLanguages),
      Object.hashAll(customRegexRules),
      hashMap(sourceFileProvenance),
    );
  }

  @override
  String toString() =>
      'LintProject(name: $name, root: $rootPath, '
      'sources: ${sourceFiles.length}, language: $language)';
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEq<K, V>(Map<K, V> a, Map<K, V> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key)) return false;
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

bool _nestedMapEq(
  Map<String, Map<String, Object?>> a,
  Map<String, Map<String, Object?>> b,
) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other == null && !b.containsKey(entry.key)) return false;
    if (!_mapEq<String, Object?>(entry.value, other ?? const {})) return false;
  }
  return true;
}
