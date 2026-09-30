// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/models/violation.dart';
import 'package:meta/meta.dart';

/// One completed lint pass — the result of invoking a single engine.
///
/// Maps onto SARIF's `run` object (SARIF §3.14) with the simplifying
/// assumption that one [Run] == one engine invocation; cross-engine
/// aggregation happens at the [ViolationStore] level, not by combining
/// multiple `runs[]` into one [Run].
///
/// `startedAt` / `finishedAt` are used by the trend store
/// (Pro) to chart historical violation counts. `engineVersion`
/// is captured at run time so trend lines correctly attribute spikes to
/// engine upgrades.
@immutable
class Run {
  /// Creates a [Run]. `id` is a stable identifier (typically a UUID
  /// or a timestamped slug) used by the trend store as the row key.
  const Run({
    required this.id,
    required this.engineId,
    required this.engineVersion,
    required this.startedAt,
    required this.finishedAt,
    required this.violations,
    this.success = true,
    this.exitCode,
    this.errorMessage,
    this.notifications = const <String>[],
  });

  /// Stable identifier for this run.
  final String id;

  /// Engine that produced this run — matches `LintEngine.id`.
  final String engineId;

  /// Engine version string as detected at invocation time
  /// (e.g. `"verilator 5.026"`).
  final String engineVersion;

  /// When the engine subprocess was spawned.
  final DateTime startedAt;

  /// When the engine subprocess exited (successfully or not).
  final DateTime finishedAt;

  /// Wall-clock duration of the run.
  Duration get duration => finishedAt.difference(startedAt);

  /// All violations the engine emitted during this run.
  final List<Violation> violations;

  /// Whether the engine completed normally. `false` means the
  /// subprocess crashed / timed out / was canceled — the [violations]
  /// list may be empty or partial.
  final bool success;

  /// Subprocess exit code, when available.
  final int? exitCode;

  /// Failure reason when [success] is `false`.
  final String? errorMessage;

  /// Engine-output lines the parser could not attribute to any violation
  /// (engine banners, format-drifted diagnostics, garbage) and that the
  /// log-and-continue contract surfaced rather than dropping silently. Lowered
  /// to SARIF `invocations[0].toolExecutionNotifications` so the skip is
  /// observable, not a silent loss. Empty for a clean run.
  final List<String> notifications;

  /// Returns a copy with overridden fields.
  Run copyWith({
    String? id,
    String? engineId,
    String? engineVersion,
    DateTime? startedAt,
    DateTime? finishedAt,
    List<Violation>? violations,
    bool? success,
    int? exitCode,
    String? errorMessage,
    List<String>? notifications,
  }) {
    return Run(
      id: id ?? this.id,
      engineId: engineId ?? this.engineId,
      engineVersion: engineVersion ?? this.engineVersion,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      violations: violations ?? this.violations,
      success: success ?? this.success,
      exitCode: exitCode ?? this.exitCode,
      errorMessage: errorMessage ?? this.errorMessage,
      notifications: notifications ?? this.notifications,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Run) return false;
    if (other.id != id) return false;
    if (other.engineId != engineId) return false;
    if (other.engineVersion != engineVersion) return false;
    if (other.startedAt != startedAt) return false;
    if (other.finishedAt != finishedAt) return false;
    if (other.success != success) return false;
    if (other.exitCode != exitCode) return false;
    if (other.errorMessage != errorMessage) return false;
    if (other.violations.length != violations.length) return false;
    for (var i = 0; i < violations.length; i++) {
      if (other.violations[i] != violations[i]) return false;
    }
    if (other.notifications.length != notifications.length) return false;
    for (var i = 0; i < notifications.length; i++) {
      if (other.notifications[i] != notifications[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    id,
    engineId,
    engineVersion,
    startedAt,
    finishedAt,
    success,
    exitCode,
    errorMessage,
    Object.hashAll(violations),
    Object.hashAll(notifications),
  );

  @override
  String toString() =>
      'Run($id, $engineId@$engineVersion, '
      '${violations.length} violations, success=$success)';
}
