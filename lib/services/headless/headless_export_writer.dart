// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:lintcrux/core/cli/cli_args_parser.dart';
import 'package:lintcrux/core/util/portable_path.dart';
import 'package:lintcrux/domain/models/run.dart';
import 'package:lintcrux/domain/models/sarif_report.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/export/violation_exporters.dart';
import 'package:lintcrux/services/sarif/sarif_writer.dart';
import 'package:path/path.dart' as p;

/// Serializes a headless run's violations to `--out` in the format
/// `--export` named.
///
/// Three of the four formats delegate straight to
/// [ViolationExporters] — there is exactly one JSON/CSV/HTML serializer
/// in the product and this is not a second one.
///
/// SARIF is the exception, and only because CI needs two things the
/// plain writer does not:
///
/// 1. **Repo-relative `artifactLocation.uri`.** Engines report absolute
///    paths and the violation model stores them that way, which is right
///    for the desktop app (click-to-source needs a real path). Uploading
///    those to GitHub code scanning produces alerts with no line
///    annotations, because nothing in the checked-out repository matches
///    `/home/runner/work/repo/repo/rtl/top.sv` as a *relative* path. So
///    every location is rewritten relative to the **repository root** and
///    that root is declared as the `%SRCROOT%` `uriBaseId`. GitHub resolves
///    a relative URI against the repository root and ignores
///    `originalUriBaseIds`, so a path relative to a project kept in a
///    subfolder (`rtl/project.lintcrux`) recorded every alert at the wrong
///    file. The root is the nearest enclosing `.git` of the project, or
///    `--sarif-root`, or the project root when neither exists; see
///    [resolveSarifRoot].
/// 2. **A stable `automationDetails.id`.** GitHub uses it to group runs
///    into a category so re-uploads supersede rather than duplicate. The
///    in-app exporter synthesizes an id containing a microsecond
///    timestamp, which would make every CI upload a brand-new category.
///
/// The desktop app's SARIF export goes through [renderSarif] as well, so a
/// file saved from the app uploads like one the CLI wrote.
class HeadlessExportWriter {
  /// Creates a [HeadlessExportWriter].
  const HeadlessExportWriter();

  /// The symbolic base id declared for the SARIF root.
  ///
  /// `%SRCROOT%` is the conventional spelling in the SARIF ecosystem and
  /// is what GitHub's ingestion documents.
  static const String srcRootBaseId = '%SRCROOT%';

  /// Writes [violations] to [outputPath] in [format].
  ///
  /// [projectRoot] is where the SARIF root is looked for; [sarifRoot] names
  /// it outright (`--sarif-root`). [runId] is the `automationDetails.id`;
  /// pass something stable across CI runs of the same workflow (the runner
  /// passes the project name).
  ///
  /// Throws [HeadlessExportException] on an unknown format or any I/O
  /// failure, so the caller can exit `CliExitCode.runFailed` rather than
  /// report a clean run that produced no artifact.
  Future<void> write({
    required Iterable<Violation> violations,
    required String format,
    required String outputPath,
    required String projectRoot,
    required String runId,
    String? sarifRoot,
    DateTime? exportTime,
    RuleDescriber? describeRule,
  }) async {
    final list = violations.toList(growable: false);
    final String contents;
    switch (format) {
      case CliArgsParser.kSarifExportFormat:
        contents = renderSarif(
          violations: list,
          projectRoot: projectRoot,
          sarifRoot: sarifRoot,
          runId: runId,
          exportTime: exportTime,
          describeRule: describeRule,
        );
      case 'json':
        contents = const ViolationExporters().toJson(list);
      case 'csv':
        contents = const ViolationExporters().toCsv(list);
      case 'html':
        contents = const ViolationExporters().toHtml(list);
      default:
        throw HeadlessExportException(
          'unknown export format "$format"; expected one of '
          '${CliArgsParser.kExportFormats.join(', ')}',
        );
    }

    final out = File(p.normalize(p.absolute(outputPath)));
    try {
      final parent = out.parent;
      if (!parent.existsSync()) {
        await parent.create(recursive: true);
      }
      await out.writeAsString(contents);
    } on FileSystemException catch (e) {
      throw HeadlessExportException(
        'could not write ${out.path}: ${e.message}',
      );
    }
  }

  /// Renders the CI-shaped SARIF document without touching the disk.
  /// Exposed separately so tests, and the desktop export, can use it.
  String renderSarif({
    required List<Violation> violations,
    required String projectRoot,
    required String runId,
    String? sarifRoot,
    DateTime? exportTime,
    RuleDescriber? describeRule,
  }) {
    final now = (exportTime ?? DateTime.now()).toUtc();
    final root = resolveSarifRoot(
      projectRoot: projectRoot,
      explicit: sarifRoot,
    );

    final byEngine = <String, List<Violation>>{};
    for (final v in violations) {
      (byEngine[v.engineId] ??= <Violation>[]).add(_relativize(v, root));
    }

    final runs = <Run>[
      for (final entry in byEngine.entries)
        Run(
          id: '$runId/${entry.key}',
          engineId: entry.key,
          engineVersion: '',
          startedAt: now,
          finishedAt: now,
          violations: entry.value,
        ),
    ];

    return SarifWriter(
      uriBaseId: srcRootBaseId,
      originalUriBaseIds: <String, String>{
        srcRootBaseId: Uri.directory(root).toString(),
      },
      describeRule: describeRule,
    ).write(SarifReport(runs: runs));
  }

  /// The directory SARIF paths are written relative to: [explicit] when
  /// given (`--sarif-root`), else the repository root enclosing
  /// [projectRoot] (see [findRepositoryRoot]), else [projectRoot] itself.
  /// Always absolute and normalized.
  static String resolveSarifRoot({
    required String projectRoot,
    String? explicit,
  }) {
    if (explicit != null && explicit.isNotEmpty) {
      return p.normalize(p.absolute(explicit));
    }
    final project = p.normalize(p.absolute(projectRoot));
    return findRepositoryRoot(project) ?? project;
  }

  /// The nearest directory at or above [directory] holding a `.git` entry,
  /// or `null` when none does. A `.git` *file* counts too: that is what a
  /// submodule and a linked work tree have, and the checkout it marks is
  /// still the repository GitHub resolves paths against.
  static String? findRepositoryRoot(String directory) {
    var dir = p.normalize(p.absolute(directory));
    while (true) {
      final marker = p.join(dir, '.git');
      if (FileSystemEntity.typeSync(marker) != FileSystemEntityType.notFound) {
        return dir;
      }
      final parent = p.dirname(dir);
      if (parent == dir) return null;
      dir = parent;
    }
  }

  /// Returns [v] with every location rewritten relative to [root].
  ///
  /// A location outside the root (a violation in a system header, or a
  /// source file the project references by an absolute path elsewhere on
  /// disk) is left absolute rather than emitted as a `../../..` escape:
  /// SARIF's `uri` is a URI reference and consumers reject upward
  /// traversal out of the base.
  static Violation _relativize(Violation v, String root) {
    final waiver = v.suppression;
    return v.copyWith(
      location: _relativizeLocation(v.location, root),
      // A suppressed result is exported with its SARIF `suppressions` entry,
      // which carries the waiver's id; an inline pragma's id embeds the
      // source path, so it is made root-relative like the locations.
      suppression: waiver?.copyWith(
        // Same portability rule as the locations below: what is left of
        // the id after the root prefix comes off is a path, and it must
        // read the same on every agent that uploads this file.
        id: _posixSeparators(waiver.id.replaceAll('$root${p.separator}', '')),
        filePath: _relativizeLocation(
          SourceLocation(file: waiver.filePath, line: 1, column: 1),
          root,
        ).file,
      ),
      relatedLocations: <SourceLocation>[
        for (final loc in v.relatedLocations) _relativizeLocation(loc, root),
      ],
      raw: _exportableRaw(v.raw, root),
    );
  }

  /// The part of a violation's raw bag that may travel in the artifact.
  ///
  /// The bag has two kinds of entry. Keys SARIF defines on a `result`
  /// (`locations`, `partialFingerprints`, …) are the *original* SARIF
  /// structures a violation was read with, and they carry the original
  /// absolute paths; `SarifWriter` spreads them back into the result, so
  /// they are dropped here rather than let a developer's home directory
  /// through any key the structured fields do not overwrite. Every other
  /// key is an engine's structured data (a CDC finding's registers,
  /// domains, width and synchronizer kind) and belongs in the result's
  /// `properties`: without it a consumer can see that a crossing was
  /// reported and where, and not which registers it connects. A string
  /// value that is an absolute path under [root] is made relative like the
  /// locations.
  static Map<String, dynamic> _exportableRaw(
    Map<String, dynamic> raw,
    String root,
  ) => <String, dynamic>{
    for (final entry in raw.entries)
      if (!SarifWriter.sarifResultKeys.contains(entry.key))
        entry.key: _relativizeValue(entry.value, root),
  };

  static Object? _relativizeValue(Object? value, String root) {
    if (value is String && p.isAbsolute(value) && p.isWithin(root, value)) {
      return portableRelativePath(value, root);
    }
    if (value is List) {
      return <Object?>[for (final e in value) _relativizeValue(e, root)];
    }
    if (value is Map) {
      return <String, dynamic>{
        for (final e in value.entries)
          e.key.toString(): _relativizeValue(e.value, root),
      };
    }
    return value;
  }

  static SourceLocation _relativizeLocation(SourceLocation loc, String root) {
    if (loc.file.isEmpty) return loc;
    if (!p.isAbsolute(loc.file)) return loc;
    if (!p.isWithin(root, loc.file)) return loc;
    // `/`-separated on every platform: this string becomes a SARIF
    // `artifactLocation.uri`, and a URI reference has exactly one
    // separator. See [portableRelativePath].
    return loc.copyWith(file: portableRelativePath(loc.file, root));
  }

  /// [value] with the host's path separator rewritten to `/`. A no-op
  /// everywhere but Windows, where [p.separator] is `\`.
  static String _posixSeparators(String value) =>
      p.separator == p.posix.separator
      ? value
      : value.replaceAll(p.separator, p.posix.separator);
}

/// Thrown when a headless export cannot be produced or written.
class HeadlessExportException implements Exception {
  /// Creates a [HeadlessExportException] with [message].
  const HeadlessExportException(this.message);

  /// Human-readable explanation, printable to stderr verbatim.
  final String message;

  @override
  String toString() => 'export failed: $message';
}
