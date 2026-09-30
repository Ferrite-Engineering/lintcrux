// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:lintcrux/domain/models/lint_baseline.dart';
import 'package:path/path.dart' as p;

/// Reads the active [LintBaseline] off disk for the headless
/// `--fail-on-new-violations` gate.
///
/// ### Why a *reader* lives in open core
///
/// The baseline **workflow** — snapshotting a run, rebasing, the
/// Baseline Diff screen, the audit trail — is Pro-tier, and its
/// persistence lives in the Pro overlay's `JsonFileBaselineStore`. What
/// is open-core is everything a CI gate actually needs: the
/// [LintBaseline] model with its own `fromJson`, the pure
/// [BaselineFilter] classifier, and this reader. The [BaselineStore]
/// interface doc already names "the CLI `--fail-on-new-violations`
/// runner" as one of its consumers.
///
/// So the division is: LintCrux Pro **writes** `.lintcrux-baseline.json`;
/// anyone's CI **reads** it. A team that has not bought Pro gets a gate
/// with no baseline, which [BaselineFilter] correctly classifies as
/// "every violation is new" — a strict gate rather than a broken one.
///
/// Missing file is not an error: `--fail-on-new-violations` on a project
/// that has never been baselined is the strict-from-day-one case, and
/// the caller reports it as a diagnostic rather than a failure.
class CliBaselineReader {
  /// Creates a [CliBaselineReader].
  const CliBaselineReader();

  /// The conventional baseline filename inside a project root. Matches
  /// what the Pro `JsonFileBaselineStore` writes.
  static const String defaultFileName = '.lintcrux-baseline.json';

  /// Resolves which file to read.
  ///
  /// [explicitPath] is the `--baseline` value; when null, the default
  /// filename inside [projectRoot] is used.
  static String resolvePath({
    required String projectRoot,
    String? explicitPath,
  }) {
    if (explicitPath != null && explicitPath.isNotEmpty) {
      return p.normalize(p.absolute(explicitPath));
    }
    return p.normalize(p.join(projectRoot, defaultFileName));
  }

  /// Reads the baseline at [path].
  ///
  /// Returns a [CliBaselineReadResult] whose `baseline` is `null` when
  /// the file does not exist. Throws nothing: a malformed baseline is
  /// reported through [CliBaselineReadResult.error] so the caller can
  /// decide (the runner treats it as a run failure — a gate reading a
  /// corrupt baseline would silently pass everything).
  Future<CliBaselineReadResult> read(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      return CliBaselineReadResult(path: path);
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return CliBaselineReadResult(
          path: path,
          error:
              'baseline file must contain a JSON object, got '
              '${decoded.runtimeType}',
        );
      }
      return CliBaselineReadResult(
        path: path,
        baseline: LintBaseline.fromJson(decoded),
      );
    } on FormatException catch (e) {
      return CliBaselineReadResult(path: path, error: e.message);
    } on FileSystemException catch (e) {
      return CliBaselineReadResult(path: path, error: e.message);
    }
  }
}

/// Outcome of [CliBaselineReader.read].
class CliBaselineReadResult {
  /// Creates a [CliBaselineReadResult].
  const CliBaselineReadResult({required this.path, this.baseline, this.error});

  /// The file that was consulted, absolute.
  final String path;

  /// The parsed baseline, or `null` when the file was absent or
  /// unreadable.
  final LintBaseline? baseline;

  /// Why the file could not be parsed, or `null` when it parsed (or
  /// simply did not exist).
  final String? error;

  /// Whether a baseline was successfully loaded.
  bool get hasBaseline => baseline != null;

  /// Whether the file existed but could not be interpreted.
  bool get isCorrupt => error != null;
}
