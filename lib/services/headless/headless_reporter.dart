// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/core/util/portable_path.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/headless/headless_run_result.dart';
import 'package:path/path.dart' as p;

/// Renders a [HeadlessRunResult] as the text the CLI prints.
///
/// Split out of `bin/lintcrux.dart` so the output format is unit-tested
/// rather than eyeballed, and so the Pro CLI reuses it verbatim.
///
/// ### English only, on purpose
///
/// Every other user-facing string in LintCrux comes from an ARB file.
/// CLI output does not, and cannot: `flutter gen-l10n` emits classes
/// that import `package:flutter/widgets.dart`, and the whole point of
/// this binary is that it has no Flutter in its dependency graph.
/// `CliArgsParser.usage` follows the same rule.
/// The localization rule governs the GUI, where a `BuildContext`
/// exists. If the CLI ever needs localizing, the answer is a
/// Flutter-free message catalog, not a `dart:ui` dependency.
class HeadlessReporter {
  /// Creates a [HeadlessReporter].
  ///
  /// [relativeTo] shortens printed file paths against a directory —
  /// normally the process working directory, so a CI log shows
  /// `rtl/top.sv` rather than `/home/runner/work/repo/repo/rtl/top.sv`.
  const HeadlessReporter({this.relativeTo, this.quiet = false});

  /// Directory printed paths are shortened against, or `null` to print
  /// them as the engines reported them.
  final String? relativeTo;

  /// When `true`, the per-violation listing is omitted.
  final bool quiet;

  /// Lines destined for stdout: the violation listing and the summary.
  ///
  /// A run that never reached the engines (a usage error, an unreadable
  /// project) produces no stdout at all: the errors are already on
  /// stderr, and printing `no violations` under them would read as a
  /// clean result. Only a run that actually executed gets a summary.
  List<String> stdoutLines(HeadlessRunResult result) {
    if (result.statuses.isEmpty && result.problems.isNotEmpty) {
      return const <String>[];
    }
    final out = <String>[];
    final reportable = result.reportableViolations;

    if (!quiet && reportable.isNotEmpty) {
      // Deterministic order: severity first (fatal → none), then file,
      // then line. A CI log diffed between runs should not churn because
      // two engines finished in a different order.
      final sorted = [...reportable]..sort(_compare);
      for (final v in sorted) {
        out.add(_formatViolation(v, result));
      }
      out.add('');
    }

    out.add(_summaryLine(result));
    return out;
  }

  /// Lines destined for stderr: diagnostics first, then fatal problems.
  List<String> stderrLines(HeadlessRunResult result) {
    return <String>[
      for (final d in result.diagnostics) 'lintcrux: note: $d',
      for (final e in result.problems) 'lintcrux: error: $e',
    ];
  }

  String _formatViolation(Violation v, HeadlessRunResult result) {
    final loc = v.location;
    final file = _shorten(loc.file);
    // `file:line:col: severity: [rule] message` — the shape every editor
    // and CI log scraper already knows how to click on.
    final buffer = StringBuffer()
      ..write('$file:${loc.line}:${loc.column}: ')
      ..write('${v.severity.name}: ')
      ..write('[${v.ruleId}] ')
      ..write(v.message);
    if (result.baselineApplied && result.newViolations.contains(v)) {
      buffer.write('  (new)');
    }
    return buffer.toString();
  }

  String _summaryLine(HeadlessRunResult result) {
    final counts = result.severityCounts;
    final parts = <String>[
      for (final s in Severity.values)
        if ((counts[s] ?? 0) > 0) '${counts[s]} ${s.name}',
    ];
    final b = StringBuffer('lintcrux: ');
    if (result.projectName != null) {
      b.write('${result.projectName}: ');
    }
    b.write(
      parts.isEmpty
          ? 'no violations'
          : '${result.reportableViolations.length} violations '
                '(${parts.join(', ')})',
    );
    if (result.suppressedCount > 0) {
      b.write(', ${result.suppressedCount} suppressed');
    }
    if (result.baselinePath != null) {
      b
        ..write(', ${result.newViolations.length} new')
        ..write(', ${result.persistingViolations.length} pre-existing');
      if (result.resolvedViolationCount > 0) {
        b.write(', ${result.resolvedViolationCount} resolved');
      }
      if (!result.baselineApplied) {
        b.write(' (no baseline found)');
      }
    }
    if (result.exportPath != null) {
      b.write(' — wrote ${_shorten(result.exportPath!)}');
    }
    b.write(' [exit ${result.exitCode}: ${result.exitLabel}]');
    return b.toString();
  }

  String _shorten(String path) {
    final base = relativeTo;
    if (base == null || path.isEmpty || !p.isAbsolute(path)) return path;
    if (!p.isWithin(base, path)) return path;
    // `/`-separated on every platform. This class's contract is the
    // `file:line:col:` shape "every editor and CI log scraper already
    // knows how to click on", and a log a mixed-platform team diffs — or
    // a scraper keyed on `rtl/top.sv` — must not change shape because the
    // job happened to land on a Windows agent. See [portableRelativePath].
    return portableRelativePath(path, base);
  }

  static int _compare(Violation a, Violation b) {
    final bySeverity = severityCompare(a.severity, b.severity);
    if (bySeverity != 0) return bySeverity;
    final byFile = a.location.file.compareTo(b.location.file);
    if (byFile != 0) return byFile;
    final byLine = a.location.line.compareTo(b.location.line);
    if (byLine != 0) return byLine;
    final byColumn = a.location.column.compareTo(b.location.column);
    if (byColumn != 0) return byColumn;
    return a.ruleId.compareTo(b.ruleId);
  }
}
