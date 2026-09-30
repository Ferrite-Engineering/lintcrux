// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/services/import/filelist_reader.dart';
import 'package:lintcrux/services/project/project_file_codec.dart';
import 'package:path/path.dart' as p;

/// High-level orchestrator that produces a `.lintcrux` project from a
/// Vivado-style `.f` filelist.
///
/// Two consumers:
///
/// 1. The "File → Import → Vivado Filelist…" menu action: pick a `.f`
///    file, choose an output `.lintcrux` path, call [importFilelist].
/// 2. The headless CLI flag `lintcrux --import-filelist <path>`:
///    constructs the project beside the filelist and exits.
///
/// The service does **not** mutate the running app's project state —
/// it returns an [ImportedProjectResult] containing the path of the
/// emitted `.lintcrux` file and the [LintProject] in memory. The
/// caller is responsible for opening the resulting project (in the UI
/// case) or printing the path (in the CLI case).
class FilelistImportService {
  /// Creates a [FilelistImportService] with an optional injected
  /// [FilelistReader] (tests use this to drive environment-variable
  /// expansion deterministically).
  const FilelistImportService({
    this.reader = const FilelistReader(),
    this.codec = const ProjectFileCodec(),
  });

  /// The reader used to parse the `.f` input.
  final FilelistReader reader;

  /// The codec used to serialize the resulting [LintProject].
  final ProjectFileCodec codec;

  /// Imports [filelistPath] into a `.lintcrux` written at [outputPath].
  ///
  /// When [outputPath] is omitted, the result is written beside the
  /// filelist with the `.lintcrux` extension (e.g. `rtl.f` →
  /// `rtl.lintcrux`).
  ///
  /// Throws [FilelistImportException] on parse / cycle / I/O errors.
  ImportedProjectResult importFilelist({
    required String filelistPath,
    String? outputPath,
    String? projectName,
    HdlLanguage projectLanguage = HdlLanguage.systemVerilog,
    List<String> enabledEngineIds = const <String>[],
  }) {
    final imported = reader.read(filelistPath);
    final absFilelist = p.normalize(p.absolute(filelistPath));
    final outPath = outputPath ?? p.setExtension(absFilelist, '.lintcrux');
    final rootPath = p.dirname(absFilelist);
    final inferredName = projectName ?? p.basenameWithoutExtension(absFilelist);
    final project = LintProject(
      name: inferredName,
      rootPath: rootPath,
      sourceFiles: imported.sourceFiles,
      includePaths: imported.includePaths,
      defines: imported.defines,
      language: projectLanguage,
      enabledEngineIds: enabledEngineIds,
    );
    final json = codec.encode(project);
    try {
      File(outPath).writeAsStringSync(json);
    } on FileSystemException catch (e) {
      // A read-only checkout, vendor tree or network mount. Every caller
      // reports this exception type and nothing else, so a bare
      // FileSystemException was an import that silently did nothing.
      throw FilelistImportException(
        'could not write "$outPath": ${e.osError?.message ?? e.message}',
      );
    }
    return ImportedProjectResult(
      project: project,
      projectFilePath: outPath,
      sourceFilelistPath: absFilelist,
    );
  }
}

/// Result of [FilelistImportService.importFilelist].
class ImportedProjectResult {
  /// Creates an [ImportedProjectResult].
  const ImportedProjectResult({
    required this.project,
    required this.projectFilePath,
    required this.sourceFilelistPath,
  });

  /// The newly created [LintProject].
  final LintProject project;

  /// Absolute path of the emitted `.lintcrux` file.
  final String projectFilePath;

  /// Absolute path of the source `.f` filelist.
  final String sourceFilelistPath;
}
