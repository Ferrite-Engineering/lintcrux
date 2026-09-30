// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/services/import/edam_reader.dart';
import 'package:lintcrux/services/project/project_file_codec.dart';
import 'package:path/path.dart' as p;

/// High-level orchestrator that produces a `.lintcrux` project from a
/// FuseSoC/Edalize EDAM (`.eda.yml`) file.
///
/// Two consumers, mirroring [FilelistImportService]:
///
/// 1. The "File → Import FuseSoC EDAM…" menu action: pick a
///    `.eda.yml`, call [importEdam], open the resulting project.
/// 2. The headless CLI flag `lintcrux --import-edam <path>`:
///    constructs the project beside the EDAM and lints it, which makes
///    `fusesoc run --target=lint --setup vendor:lib:core` followed by
///    `lintcrux --import-edam build/…/*.eda.yml --sarif out.sarif`
///    a complete FuseSoC → LintCrux pipeline with no hand-editing.
///
/// The service does **not** mutate the running app's project state —
/// it returns an [ImportedEdamProjectResult] with the emitted
/// `.lintcrux` path, the in-memory [LintProject], and the reader's
/// warnings. The caller opens the project (UI) or prints the path and
/// warnings (CLI).
class EdamImportService {
  /// Creates an [EdamImportService] with an optional injected
  /// [EdamReader] / [ProjectFileCodec].
  const EdamImportService({
    this.reader = const EdamReader(),
    this.codec = const ProjectFileCodec(),
  });

  /// The reader used to parse the `.eda.yml` input.
  final EdamReader reader;

  /// The codec used to serialize the resulting [LintProject].
  final ProjectFileCodec codec;

  /// Imports [edamPath] into a `.lintcrux` written at [outputPath].
  ///
  /// When [outputPath] is omitted, the result is written beside the
  /// EDAM with the `.lintcrux` extension, stripping the full
  /// `.eda.yml` double extension (`design.eda.yml` →
  /// `design.lintcrux`).
  ///
  /// Throws [EdamImportException] on parse / I/O errors or an EDAM
  /// with no lintable sources.
  ImportedEdamProjectResult importEdam({
    required String edamPath,
    String? outputPath,
    String? projectName,
    List<String> enabledEngineIds = const <String>[],
  }) {
    final imported = reader.read(edamPath);
    final absEdam = p.normalize(p.absolute(edamPath));
    final outPath = outputPath ?? _defaultOutputPath(absEdam);
    // The EDAM sits in the FuseSoC work root; the staged sources live
    // under `src/` beside it, so the work root is the natural project
    // root even though every stored path is absolute.
    final rootPath = p.dirname(absEdam);
    final inferredName =
        projectName ?? imported.name ?? _basenameWithoutEdamExtension(absEdam);

    final verilatorOptions = <String, Object?>{
      if (imported.verilatorWarnFlags != null)
        'warnFlags': imported.verilatorWarnFlags,
      if (imported.verilatorExtraOptions.isNotEmpty)
        'extraOptions': imported.verilatorExtraOptions,
      if (imported.verilatorWaiverFiles.isNotEmpty)
        'waiverFiles': imported.verilatorWaiverFiles,
    };

    final project = LintProject(
      name: inferredName,
      rootPath: rootPath,
      sourceFiles: imported.sourceFiles,
      includePaths: imported.includePaths,
      defines: imported.defines,
      topModule: imported.toplevel,
      language: imported.language,
      enabledEngineIds: enabledEngineIds,
      perEngineOptions: <String, Map<String, Object?>>{
        if (verilatorOptions.isNotEmpty) 'verilator': verilatorOptions,
      },
      sourceFileLanguages: imported.sourceFileLanguages,
      sourceFileProvenance: imported.sourceFileProvenance,
    );
    final json = codec.encode(project);
    try {
      File(outPath).writeAsStringSync(json);
    } on FileSystemException catch (e) {
      // A read-only checkout, vendor tree or network mount. Every caller
      // reports this exception type and nothing else, so a bare
      // FileSystemException was an import that silently did nothing.
      throw EdamImportException(
        'could not write "$outPath": ${e.osError?.message ?? e.message}',
      );
    }
    return ImportedEdamProjectResult(
      project: project,
      projectFilePath: outPath,
      sourceEdamPath: absEdam,
      warnings: imported.warnings,
    );
  }

  /// `design.eda.yml` → `design.lintcrux`. `p.setExtension` alone
  /// would produce `design.eda.lintcrux` because it only strips the
  /// final extension.
  String _defaultOutputPath(String absEdam) => p.join(
    p.dirname(absEdam),
    '${_basenameWithoutEdamExtension(absEdam)}.lintcrux',
  );

  String _basenameWithoutEdamExtension(String absEdam) {
    final base = p.basename(absEdam);
    if (base.endsWith('.eda.yml')) {
      return base.substring(0, base.length - '.eda.yml'.length);
    }
    return p.basenameWithoutExtension(base);
  }
}

/// Result of [EdamImportService.importEdam].
class ImportedEdamProjectResult {
  /// Creates an [ImportedEdamProjectResult].
  const ImportedEdamProjectResult({
    required this.project,
    required this.projectFilePath,
    required this.sourceEdamPath,
    required this.warnings,
  });

  /// The newly created [LintProject].
  final LintProject project;

  /// Absolute path of the emitted `.lintcrux` file.
  final String projectFilePath;

  /// Absolute path of the source `.eda.yml` EDAM file.
  final String sourceEdamPath;

  /// The reader's non-fatal warnings (skipped file types, ignored
  /// tool options, version drift). The CLI prints these to stderr;
  /// the GUI logs them.
  final List<String> warnings;
}
