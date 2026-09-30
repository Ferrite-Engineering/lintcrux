// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:meta/meta.dart';

/// A single source file declared in a `.lintcrux` project, with its
/// per-file language.
///
/// The original schema stored sources as plain `List<String>` and
/// inferred language from the project-level `LintProject.language`.
/// Mixed-language designs (Verilog + VHDL in the same project) need the
/// per-file language to live with the path.
///
/// The default [ProjectSourceFileLanguage.auto] keeps plain-string
/// files working unchanged — the engine routing layer falls back to
/// extension-based detection when the language is `auto`, so older
/// `.lintcrux` files load with `auto` and newer files can declare
/// explicit per-file languages.
@immutable
class ProjectSourceFile {
  /// Creates a [ProjectSourceFile].
  const ProjectSourceFile({
    required this.path,
    this.language = ProjectSourceFileLanguage.auto,
  });

  /// Absolute or project-root-relative path to the source file. The
  /// engine layer is responsible for resolving relative paths against
  /// `LintProject.rootPath`.
  final String path;

  /// Per-file source language. [ProjectSourceFileLanguage.auto] means
  /// "detect from extension at engine-routing time" — the file extension
  /// → language mapping is:
  ///   - `.v`, `.vh` → verilog
  ///   - `.sv`, `.svh` → systemVerilog
  ///   - `.vhd`, `.vhdl` → vhdl
  ///
  /// The lookup is case-insensitive and falls back to systemVerilog if
  /// no rule matches.
  final ProjectSourceFileLanguage language;

  /// Returns this file's effective [HdlLanguage]. When [language] is
  /// [ProjectSourceFileLanguage.auto], dispatches to extension-based
  /// detection; otherwise honors the explicit declaration.
  HdlLanguage resolveLanguage() {
    switch (language) {
      case ProjectSourceFileLanguage.verilog:
        return HdlLanguage.verilog;
      case ProjectSourceFileLanguage.systemVerilog:
        return HdlLanguage.systemVerilog;
      case ProjectSourceFileLanguage.vhdl:
        return HdlLanguage.vhdl;
      case ProjectSourceFileLanguage.auto:
        return _languageFromExtension(path);
    }
  }

  /// Returns a copy with overridden fields.
  ProjectSourceFile copyWith({
    String? path,
    ProjectSourceFileLanguage? language,
  }) {
    return ProjectSourceFile(
      path: path ?? this.path,
      language: language ?? this.language,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ProjectSourceFile &&
      other.path == path &&
      other.language == language;

  @override
  int get hashCode => Object.hash(path, language);

  @override
  String toString() => 'ProjectSourceFile($path, $language)';

  static HdlLanguage _languageFromExtension(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.vhd') || lower.endsWith('.vhdl')) {
      return HdlLanguage.vhdl;
    }
    if (lower.endsWith('.sv') || lower.endsWith('.svh')) {
      return HdlLanguage.systemVerilog;
    }
    if (lower.endsWith('.v') || lower.endsWith('.vh')) {
      return HdlLanguage.verilog;
    }
    // Unknown extension — default to systemVerilog (the superset).
    return HdlLanguage.systemVerilog;
  }
}

/// Per-source-file language declaration in the `.lintcrux` schema.
///
/// [auto] is the default and matches the original behavior of inferring
/// language from the file extension. Explicit values are needed for
/// projects where the extension is misleading (e.g. legacy `.v` files
/// that are actually SystemVerilog) and for mixed-language designs
/// where a single `LintProject.language` value is insufficient.
enum ProjectSourceFileLanguage {
  /// Inferred at engine-routing time from the file extension.
  /// (The default — preserves the plain-string schema's behavior.)
  auto,

  /// IEEE 1364 Verilog.
  verilog,

  /// IEEE 1800 SystemVerilog.
  systemVerilog,

  /// IEEE 1076 VHDL.
  vhdl,
}
