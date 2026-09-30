// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/project_source_file.dart';
import 'package:lintcrux/services/project/project_file_service.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Turns the CLI's positional arguments into a single [LintProject] the
/// headless runner can execute — or into an explicit list of complaints.
///
/// Two input shapes are supported, and they do not mix:
///
/// 1. **Project mode** — exactly one `.lintcrux` positional. Its
///    `sourceFiles` / `includePaths` are resolved against the project
///    file's own directory so `lintcrux path/to/project.lintcrux` works
///    from any working directory, which is the only thing a CI job can
///    rely on.
/// 2. **Ad-hoc mode** — one or more HDL source files
///    (`.v` / `.sv` / `.svh` / `.vh` / `.vhd` / `.vhdl`). A synthetic
///    project is built around them, rooted at their common ancestor
///    directory, with the language inferred from the extensions and the
///    top module taken from `--top`.
///
/// ### Why this class reports instead of skipping
///
/// The pre-headless behavior was that a non-`.lintcrux` positional was
/// dropped on the floor: `lintcrux typo.sv` opened an empty window and
/// `lintcrux rtl/*.sv` linted nothing. In a pipeline that becomes a
/// green build over zero files — the same "silent false clean" defect
/// class that `EngineRunFailedException` exists to close on the engine
/// side. So every positional this resolver cannot use lands in
/// [HeadlessInputResolution.problems]. The caller exits `CliExitCode.usage`
/// for a command line that names nothing usable, and `CliExitCode.runFailed`
/// for a project that exists but cannot be loaded
/// ([HeadlessInputResolution.kind]).
class HeadlessInputResolver {
  /// Creates a [HeadlessInputResolver].
  const HeadlessInputResolver({
    this.projectFileService = const ProjectFileService(),
  });

  /// Reader for `.lintcrux` files. Injectable for tests.
  final ProjectFileService projectFileService;

  /// The project-file extension, including the leading dot.
  static const String projectExtension = '.lintcrux';

  /// Printed when the command line carries no positional arguments at
  /// all. A bare `lintcrux` in a pipeline is a mis-wired step, not a
  /// request to lint the empty set.
  static const String _noInputMessage =
      'No input. Pass a .lintcrux project file, or one or more '
      '.v / .sv / .vhd source files.';

  /// Extensions accepted as ad-hoc HDL sources, lowercase, with the
  /// leading dot. Mirrors the set `ProjectSourceFile.resolveLanguage`
  /// knows how to classify.
  static const List<String> sourceExtensions = <String>[
    '.v',
    '.vh',
    '.sv',
    '.svh',
    '.vhd',
    '.vhdl',
  ];

  /// Resolves [paths] (the positional arguments, in invocation order).
  ///
  /// [topModule] is the `--top` value: it sets the synthetic project's
  /// top module in ad-hoc mode, and overrides the loaded project's
  /// declared top module in project mode.
  Future<HeadlessInputResolution> resolve(
    List<String> paths, {
    String? topModule,
  }) async {
    if (paths.isEmpty) {
      return const HeadlessInputResolution.failed(<String>[_noInputMessage]);
    }

    final problems = <String>[];
    final projectPaths = <String>[];
    final sourcePaths = <String>[];

    for (final raw in paths) {
      final ext = p.extension(raw).toLowerCase();
      if (ext == projectExtension) {
        projectPaths.add(raw);
        continue;
      }
      if (sourceExtensions.contains(ext)) {
        sourcePaths.add(raw);
        continue;
      }
      // Neither a project nor a source file. Say so — a positional the
      // tool cannot use must never be silently dropped.
      if (Directory(raw).existsSync()) {
        problems.add(
          '"$raw" is a directory. LintCrux does not glob directories; '
          'pass the source files (your shell can expand them) or a '
          '.lintcrux project file.',
        );
      } else {
        problems.add(
          '"$raw" is not a .lintcrux project file and does not have a '
          'lintable HDL extension '
          '(${sourceExtensions.join(', ')}).',
        );
      }
    }

    if (projectPaths.isNotEmpty && sourcePaths.isNotEmpty) {
      problems.add(
        'Cannot mix a .lintcrux project (${projectPaths.first}) with '
        'loose source files (${sourcePaths.first}). Run them separately, '
        'or add the sources to the project file.',
      );
    }
    if (projectPaths.length > 1) {
      problems.add(
        'Expected at most one .lintcrux project file; got '
        '${projectPaths.length} (${projectPaths.join(', ')}). The '
        'headless runner lints one project per invocation.',
      );
    }
    if (problems.isNotEmpty) {
      return HeadlessInputResolution.failed(problems);
    }

    if (projectPaths.length == 1) {
      return await _resolveProject(projectPaths.single, topModule: topModule);
    }
    return await _resolveAdHoc(sourcePaths, topModule: topModule);
  }

  Future<HeadlessInputResolution> _resolveProject(
    String projectPath, {
    required String? topModule,
  }) async {
    final absProjectPath = p.normalize(p.absolute(projectPath));
    if (!File(absProjectPath).existsSync()) {
      return HeadlessInputResolution.failed(<String>[
        'Project file not found: $absProjectPath',
      ]);
    }
    final LintProject loaded;
    try {
      loaded = await projectFileService.read(absProjectPath);
    } on Object catch (e) {
      // The file exists and is not a project LintCrux can read: the input
      // is broken, not the command line.
      return HeadlessInputResolution.failed(
        <String>['$e'],
        kind: HeadlessInputFailureKind.loadFailed,
      );
    }

    // Relative entries in a `.lintcrux` resolve against the directory
    // holding the project file, not against the process CWD. The GUI can
    // get away with the looser reading because a user picks the file
    // from a dialog; a CI job invoking `lintcrux rtl/proj.lintcrux` from
    // the repo root cannot.
    //
    // `rootPath` is the exception, and it is not one this code invented:
    // committed `.lintcrux` files in the tree carry a `rootPath` that is
    // relative *to the repository root* and names the project's own
    // directory (e.g. `"test/fixtures/projects/basic_warnings"`). Joining
    // that against the project file's directory produces a doubled path,
    // which then silently defeats the SARIF relativization — every
    // `artifactLocation.uri` stays absolute and GitHub code scanning
    // annotates nothing. So: an absolute `rootPath` is honored as
    // written; a relative one is discarded in favor of the directory the
    // project file actually lives in, which is the only value a CI job
    // can derive without knowing the author's checkout layout.
    final base = p.dirname(absProjectPath);
    final project = loaded.copyWith(
      rootPath: p.isAbsolute(loaded.rootPath)
          ? p.normalize(loaded.rootPath)
          : base,
      sourceFiles: <String>[
        for (final f in loaded.sourceFiles) _absoluteAgainst(base, f),
      ],
      includePaths: <String>[
        for (final d in loaded.includePaths) _absoluteAgainst(base, d),
      ],
      sourceFileLanguages: <String, ProjectSourceFileLanguage>{
        for (final entry in loaded.sourceFileLanguages.entries)
          _absoluteAgainst(base, entry.key): entry.value,
      },
      topModule: (topModule != null && topModule.isNotEmpty)
          ? topModule
          : loaded.topModule,
    );

    final missing = <String>[
      for (final f in project.sourceFiles)
        if (!File(f).existsSync()) f,
    ];
    if (project.sourceFiles.isEmpty) {
      return HeadlessInputResolution.failed(
        <String>['Project "${project.name}" declares no source files.'],
        kind: HeadlessInputFailureKind.loadFailed,
      );
    }
    if (missing.isNotEmpty) {
      return HeadlessInputResolution.failed(
        <String>[
          for (final f in missing)
            'Source file listed in the project is missing: $f',
        ],
        kind: HeadlessInputFailureKind.loadFailed,
      );
    }

    return HeadlessInputResolution.ok(
      project: project,
      projectFilePath: absProjectPath,
    );
  }

  Future<HeadlessInputResolution> _resolveAdHoc(
    List<String> sourcePaths, {
    required String? topModule,
  }) async {
    final absolute = <String>[
      for (final s in sourcePaths) p.normalize(p.absolute(s)),
    ];
    final missing = <String>[
      for (final f in absolute)
        if (!File(f).existsSync()) f,
    ];
    if (missing.isNotEmpty) {
      return HeadlessInputResolution.failed(<String>[
        for (final f in missing) 'Source file not found: $f',
      ]);
    }

    final root = _commonAncestor(absolute);
    return HeadlessInputResolution.ok(
      project: LintProject(
        name: topModule ?? p.basenameWithoutExtension(absolute.first),
        rootPath: root,
        sourceFiles: List<String>.unmodifiable(absolute),
        topModule: (topModule != null && topModule.isNotEmpty)
            ? topModule
            : null,
        language: _languageOf(absolute),
      ),
      projectFilePath: null,
    );
  }

  /// Infers the project-level [HdlLanguage] from an ad-hoc file list.
  /// A list spanning both HDL families is [HdlLanguage.mixed]; the
  /// per-engine router then hands each engine only the files it accepts.
  static HdlLanguage _languageOf(List<String> files) {
    var sawVhdl = false;
    var sawVerilog = false;
    for (final f in files) {
      switch (p.extension(f).toLowerCase()) {
        case '.vhd':
        case '.vhdl':
          sawVhdl = true;
        default:
          sawVerilog = true;
      }
    }
    if (sawVhdl && sawVerilog) return HdlLanguage.mixed;
    if (sawVhdl) return HdlLanguage.vhdl;
    return HdlLanguage.systemVerilog;
  }

  static String _absoluteAgainst(String base, String path) {
    if (path.isEmpty) return base;
    if (p.isAbsolute(path)) return p.normalize(path);
    return p.normalize(p.join(base, path));
  }

  static String _commonAncestor(List<String> files) {
    var dir = p.dirname(files.first);
    for (final f in files.skip(1)) {
      final other = p.dirname(f);
      while (!p.equals(dir, other) && !p.isWithin(dir, other)) {
        final parent = p.dirname(dir);
        if (parent == dir) return dir;
        dir = parent;
      }
    }
    return dir;
  }
}

/// Result of [HeadlessInputResolver.resolve] — either a runnable project
/// or a non-empty list of human-readable problems.
@immutable
class HeadlessInputResolution {
  /// A successful resolution.
  const HeadlessInputResolution.ok({
    required LintProject this.project,
    required this.projectFilePath,
  }) : problems = const <String>[],
       kind = HeadlessInputFailureKind.usage;

  /// A failed resolution carrying at least one problem string.
  const HeadlessInputResolution.failed(
    this.problems, {
    this.kind = HeadlessInputFailureKind.usage,
  }) : project = null,
       projectFilePath = null;

  /// The resolved project, or `null` when [problems] is non-empty.
  final LintProject? project;

  /// Absolute path of the `.lintcrux` file the project came from, or
  /// `null` in ad-hoc mode. Used to site the default baseline file and
  /// to resolve a `--config` overlay path.
  final String? projectFilePath;

  /// Human-readable problems, each suitable for printing to stderr
  /// verbatim. Empty on success.
  final List<String> problems;

  /// Why the resolution failed. Meaningless on success.
  final HeadlessInputFailureKind kind;

  /// Whether a project was resolved.
  bool get isSuccess => project != null;
}

/// Why a [HeadlessInputResolution] failed — the difference between exit
/// `64` and exit `3`.
enum HeadlessInputFailureKind {
  /// The command line names nothing usable: no input, a positional that is
  /// neither a project nor a lintable source, a directory, a project mixed
  /// with loose sources, more than one project, or a path that does not
  /// exist. The pipeline is mis-wired.
  usage,

  /// The command line named a project that exists but cannot be loaded: it
  /// does not parse, it declares no sources, or a source it lists is
  /// missing. The input is broken.
  loadFailed,
}
