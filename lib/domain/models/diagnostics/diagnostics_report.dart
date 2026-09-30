// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:meta/meta.dart';

/// What a version probe reports for an engine that did not answer: the
/// probe ran, and the binary was missing, refused to start, or printed
/// nothing usable. A measured outcome, not a placeholder.
const String kEngineNotDetected = 'not detected';

/// One engine's entry in a [TabDiagnosticsReport].
///
/// Every optional field is **measured or absent**. A diagnostics report is
/// what a user attaches to a bug report, so a line the app did not measure
/// is left out rather than filled with a stand-in: a made-up value in a bug
/// report is worse than a missing one, because the reader cannot tell it
/// apart from a real reading.
@immutable
class EngineDiagnostics {
  /// Creates an [EngineDiagnostics].
  const EngineDiagnostics({
    required this.engineId,
    this.binary,
    this.version,
    this.durationMs,
    this.severityCounts = const <Severity, int>{},
  });

  /// The engine's registry id (`verilator`, `cdc`, …).
  final String engineId;

  /// Where the engine's executable comes from, as configured in Settings >
  /// Engines: `custom: <path>`, `bundled: <path>`, or `PATH` when the
  /// executable is looked up on the engine `PATH` at spawn time. `null`
  /// where engines never run (the browser).
  final String? binary;

  /// What the binary itself printed for its version probe, or
  /// [kEngineNotDetected] when the probe ran and got no answer. `null` when
  /// no probe result exists yet, or engines never run (the browser).
  final String? version;

  /// Wall time of this engine's most recent run in this tab. `null` when the
  /// engine has not started in this tab.
  final int? durationMs;

  /// Violations this engine currently reports, by severity. Only non-zero
  /// severities are present.
  final Map<Severity, int> severityCounts;
}

/// Snapshot of the active tab's diagnostics-drawer content.
///
/// Used by `Copy Tab Diagnostics Report` to produce a structured
/// plain-text bundle for GitHub-issue paste.
@immutable
class TabDiagnosticsReport {
  /// Creates a [TabDiagnosticsReport].
  const TabDiagnosticsReport({
    required this.projectPath,
    required this.sourceFileCount,
    required this.engines,
    this.lastRunWallMs,
  });

  /// Project root path.
  final String projectPath;

  /// Number of source files in the project.
  final int sourceFileCount;

  /// Wall time of the most recent run, in milliseconds: the longest of the
  /// per-engine durations, since the engines run in parallel. `null` when no
  /// engine has started in this tab.
  final int? lastRunWallMs;

  /// One entry per registered engine, in registry order.
  final List<EngineDiagnostics> engines;

  /// Renders a structured plain-text dump suitable for clipboard paste
  /// into a GitHub issue. Absent values produce no line at all.
  String toPlainText() {
    final buf = StringBuffer()
      ..writeln('# LintCrux Tab Diagnostics')
      ..writeln()
      ..writeln('Project: $projectPath')
      ..writeln('Source files: $sourceFileCount');
    final wall = lastRunWallMs;
    if (wall != null) buf.writeln('Last run wall time: $wall ms');
    buf
      ..writeln()
      ..writeln('## Engines');
    for (final e in engines) {
      buf
        ..writeln()
        ..writeln('### ${e.engineId}');
      if (e.binary != null) buf.writeln('  binary: ${e.binary}');
      if (e.version != null) buf.writeln('  version: ${e.version}');
      if (e.durationMs != null) buf.writeln('  duration: ${e.durationMs} ms');
      if (e.severityCounts.isNotEmpty) {
        buf.writeln('  counts:');
        for (final s in Severity.values) {
          final n = e.severityCounts[s];
          if (n != null && n > 0) buf.writeln('    ${s.name}: $n');
        }
      }
    }
    return buf.toString();
  }
}

/// Process-wide app diagnostics snapshot.
@immutable
class AppDiagnosticsReport {
  /// Creates an [AppDiagnosticsReport].
  const AppDiagnosticsReport({
    required this.activeTabViolationCount,
    this.residentMemoryBytes,
  });

  /// The process's resident set size when the report was taken, in bytes.
  /// This is the whole process as the operating system counts it (Dart heap,
  /// engine, native libraries), which is the number that matters when the
  /// app is using too much memory. `null` where the platform cannot report
  /// it (the browser).
  final int? residentMemoryBytes;

  /// Violations the active tab currently holds.
  final int activeTabViolationCount;

  /// Renders a structured plain-text dump for clipboard paste. Absent values
  /// produce no line at all.
  String toPlainText() {
    final buf = StringBuffer()
      ..writeln('# LintCrux App Diagnostics')
      ..writeln();
    final rss = residentMemoryBytes;
    if (rss != null) {
      buf.writeln(
        'Resident memory: ${(rss / 1024 / 1024).toStringAsFixed(1)} MiB',
      );
    }
    buf.writeln('Violations in the active tab: $activeTabViolationCount');
    return buf.toString();
  }
}
