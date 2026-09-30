// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/enums/severity.dart';

/// Which violation field a cross-project search matches against.
enum CrossProjectSearchScope {
  /// Rule id, message and file path.
  all,

  /// Namespaced rule ids (`verilator/UNUSEDSIGNAL`).
  ruleId,

  /// Engine-reported violation messages.
  message,

  /// Source file paths.
  filePath,
}

/// A cross-project search request.
@immutable
class CrossProjectSearchQuery {
  /// Creates a query.
  const CrossProjectSearchQuery({
    required this.text,
    this.scope = CrossProjectSearchScope.all,
    this.caseSensitive = false,
  });

  /// The needle. An empty or whitespace-only needle matches nothing —
  /// returning every violation in every project would be a denial of
  /// service dressed as a feature.
  final String text;

  /// Which field(s) to match.
  final CrossProjectSearchScope scope;

  /// Whether matching is case-sensitive.
  final bool caseSensitive;

  /// True when this query is worth running.
  bool get isRunnable => text.trim().isNotEmpty;
}

/// One match, carrying enough to render a row and jump to it.
@immutable
class CrossProjectSearchMatch {
  /// Creates a match.
  const CrossProjectSearchMatch({
    required this.projectId,
    required this.projectName,
    required this.ruleId,
    required this.message,
    required this.filePath,
    required this.line,
    required this.severity,
  });

  /// Owning project's registry id.
  final String projectId;

  /// Owning project's display name.
  final String projectName;

  /// Namespaced rule id.
  final String ruleId;

  /// Engine message.
  final String message;

  /// Source file.
  final String filePath;

  /// 1-based line.
  final int line;

  /// Violation severity, for the row's leading icon.
  final Severity severity;
}

/// Results for one project, kept separate so the UI can group by project
/// and report per-project truncation honestly.
@immutable
class CrossProjectSearchProjectResult {
  /// Creates a per-project result.
  const CrossProjectSearchProjectResult({
    required this.projectId,
    required this.projectName,
    required this.matches,
    required this.totalMatchCount,
  });

  /// Registry id.
  final String projectId;

  /// Display name.
  final String projectName;

  /// The matches actually returned (possibly capped).
  final List<CrossProjectSearchMatch> matches;

  /// How many matched in total, before any cap.
  final int totalMatchCount;

  /// True when [matches] is a subset of what matched.
  bool get isTruncated => totalMatchCount > matches.length;
}

/// Searches every open project's violations.
///
/// **Declared here, implemented and read only by the Pro overlay, and
/// synchronous by design.** SimCrux's equivalent spawns
/// one isolate per project because it walks the file system. LintCrux does
/// not: the violations are already parsed and in memory, so a scan is a
/// list filter over data the app is holding anyway. Spawning isolates to
/// filter an in-memory list would add latency and complexity to buy
/// nothing.
// An interface, not a function typedef: the Pro implementation carries
// per-project state (registry + store family reads) and the seam has to
// be overridable as a unit.
abstract class CrossProjectSearchService {
  /// Runs [query] across the open projects.
  List<CrossProjectSearchProjectResult> search(CrossProjectSearchQuery query);
}

/// Default: finds nothing.
///
/// Open core ships `NoopProjectRegistry` (a single project, no registry),
/// so there is no "across projects" to search. The Pro overlay installs the
/// real implementation alongside the persistent registry.
class NoopCrossProjectSearchService implements CrossProjectSearchService {
  /// Const default.
  const NoopCrossProjectSearchService();

  @override
  List<CrossProjectSearchProjectResult> search(
    CrossProjectSearchQuery query,
  ) => const <CrossProjectSearchProjectResult>[];
}

/// The active [CrossProjectSearchService].
final Provider<CrossProjectSearchService> crossProjectSearchServiceProvider =
    Provider<CrossProjectSearchService>(
      (ref) => const NoopCrossProjectSearchService(),
    );
