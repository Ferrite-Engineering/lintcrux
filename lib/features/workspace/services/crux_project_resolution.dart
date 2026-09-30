// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_project/crux_project.dart';
import 'package:path/path.dart' as p;

/// The `<design>.crux-project` `artifacts:` key LintCrux consumes.
///
/// The key lives here rather than in `crux_project` on purpose: artifact kinds
/// are opaque strings in the shared package, so each product owns the constant
/// for the kind it consumes.
const String kLintArtifactKind = 'lint';

/// The outcome of pointing LintCrux at a path that might be a design manifest.
sealed class CruxProjectResolution {
  const CruxProjectResolution();
}

/// The path was not a manifest — open it as an ordinary `.lintcrux` project.
class NotAManifest extends CruxProjectResolution {
  /// Creates the pass-through outcome.
  const NotAManifest(this.path);

  /// The path, unchanged.
  final String path;
}

/// The manifest named a lint project and it is on disk.
class ManifestLintProject extends CruxProjectResolution {
  /// Creates the success outcome.
  const ManifestLintProject({
    required this.lintProjectPath,
    required this.designId,
    required this.displayName,
    this.warnings = const <String>[],
    this.legacyRenameTo,
  });

  /// The `.lintcrux` project (or the directory holding one) to open.
  final String lintProjectPath;

  /// CXP design id, derived from the manifest's directory.
  final String designId;

  /// The manifest's human label.
  final String displayName;

  /// Non-fatal parse warnings, in English.
  final List<String> warnings;

  /// The file name to rename a legacy bare `.crux-project` to, or null when
  /// the manifest already has a `<design>.crux-project` name.
  ///
  /// Carried as data rather than as the parser's English warning so the UI
  /// can show the notice in the user's language.
  final String? legacyRenameTo;
}

/// The manifest's directory holds more than one manifest, so the design is
/// ambiguous and nothing is opened.
class ManifestAmbiguous extends CruxProjectResolution {
  /// Creates the refusal outcome.
  const ManifestAmbiguous(this.error);

  /// The shared package's description of the conflict: the directory and
  /// every manifest in it.
  final CruxProjectAmbiguousException error;
}

/// The path was a manifest but there is nothing here for LintCrux.
class ManifestUnusable extends CruxProjectResolution {
  /// Creates the refusal outcome.
  const ManifestUnusable(this.message);

  /// User-facing explanation.
  final String message;
}

/// Whether [path] is something the desktop app opens as a project: a
/// `.lintcrux` project file, or a `<design>.crux-project` design manifest
/// (which [CruxProjectResolver] swaps for the lint project it names).
///
/// The manifest test is [CruxProjectParser.isManifestPath]: the
/// `crux-project` extension, compared case-insensitively, after a non-empty
/// name — or the legacy bare `.crux-project`, which still opens.
bool isOpenableProjectPath(String path) =>
    path.endsWith('.lintcrux') || CruxProjectParser.isManifestPath(path);

/// Resolves a possible design manifest path to the lint project LintCrux
/// opens.
class CruxProjectResolver {
  /// Creates a resolver.
  const CruxProjectResolver({this.parser = const CruxProjectParser()});

  /// The manifest parser. Injectable for tests.
  final CruxProjectParser parser;

  /// Resolves [path].
  CruxProjectResolution resolve(
    String path, {
    bool Function(String path)? exists,
  }) {
    if (!CruxProjectParser.isManifestPath(path)) return NotAManifest(path);

    // A design directory holds exactly one manifest. When a second one sits
    // beside the file the user chose — a renamed copy next to the legacy
    // `.crux-project`, say — the two can describe the design differently and
    // the user may not know which is stale, so nothing is opened until the
    // extras are removed.
    try {
      CruxProjectParser.findIn(p.dirname(path));
    } on CruxProjectAmbiguousException catch (e) {
      return ManifestAmbiguous(e);
    }

    final CruxProjectManifest manifest;
    try {
      manifest = parser.parseFile(path);
    } on CruxProjectFormatException catch (e) {
      return ManifestUnusable('Not a valid design manifest — ${e.message}');
    }

    final plan = const CruxProjectOpenPlanner().plan(
      manifest,
      kind: kLintArtifactKind,
      exists: exists,
    );

    final artifact = plan.artifactPath;
    if (artifact != null) {
      return ManifestLintProject(
        lintProjectPath: artifact,
        designId: plan.designId,
        displayName: manifest.displayName,
        warnings: manifest.warnings,
        legacyRenameTo: CruxProjectParser.isLegacyManifestPath(path)
            ? suggestedManifestFileName(manifest.directory)
            : null,
      );
    }

    return ManifestUnusable(
      switch (plan.refusal) {
        CruxOpenRefusal.pathMissing =>
          'The lint project this design names is missing: '
              '${manifest.rawArtifacts[kLintArtifactKind]}',
        CruxOpenRefusal.kindAbsent || null =>
          '${manifest.displayName} does not name a lint project yet. '
              'Add a `lint:` entry under `artifacts:` in its '
              '${p.basename(path)} file.',
      },
    );
  }
}

/// The `<design>.crux-project` file name for a manifest in [directory]: the
/// directory's own name, or `design` when it has none.
String suggestedManifestFileName(String directory) {
  final stem = p.basename(p.normalize(directory));
  final name = stem.isEmpty || stem == p.separator || stem == '.'
      ? 'design'
      : stem;
  return '$name.$kCruxProjectExtension';
}
