// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/project_source_file.dart';
import 'package:path/path.dart' as p;

/// Resolves a freshly-loaded [project]'s paths to ABSOLUTE form,
/// anchored at [projectFileDir] — the directory that holds the opened
/// `.lintcrux` file.
///
/// `.lintcrux` files store paths as authored: `rootPath` and the source
/// / include lists are typically relative (a committed project uses
/// `"."` for the root and bare filenames for its sources so the file is
/// portable across checkouts). The GUI open flow loads the file from a
/// picker path, so the absolute `.lintcrux` path — and therefore its
/// directory, the real project root — is known at load time even though
/// the file itself never records it. This helper threads that anchor in:
///
///  - `rootPath`: an absolute value is honored as authored (normalized);
///    a relative one is replaced by [projectFileDir] — the only root a
///    GUI (or a CI job invoking `lintcrux rtl/proj.lintcrux`) can derive
///    without knowing the author's checkout layout. This mirrors the
///    headless `HeadlessInputResolver`, so a design lints identically in
///    the desktop app and in CI.
///  - `sourceFiles`, `includePaths`, and the keys of
///    `sourceFileLanguages`: made absolute against that base so engines
///    resolve them regardless of the process working directory (a
///    Finder/Dock launch inherits CWD `/`, where every relative path is
///    invisible).
///
/// The returned project is the RUN / ENGINE-facing form. The authored
/// (relative) form is what belongs on disk: callers that re-serialize a
/// project must persist the authored paths, not the value this returns.
LintProject resolveProjectPaths(LintProject project, String projectFileDir) {
  final base = p.isAbsolute(project.rootPath)
      ? p.normalize(project.rootPath)
      : p.normalize(projectFileDir);

  String abs(String path) =>
      p.isAbsolute(path) ? p.normalize(path) : p.normalize(p.join(base, path));

  return project.copyWith(
    rootPath: base,
    sourceFiles: <String>[for (final f in project.sourceFiles) abs(f)],
    includePaths: <String>[for (final d in project.includePaths) abs(d)],
    sourceFileLanguages: <String, ProjectSourceFileLanguage>{
      for (final e in project.sourceFileLanguages.entries) abs(e.key): e.value,
    },
  );
}
