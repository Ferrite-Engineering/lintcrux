// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Per-engine status during a [ParallelEngineRunner] run.
///
/// Each engine in the active project advances through these phases
/// independently: a fast engine can complete while a slow one is still
/// running. The UI watches `runStatusFor(engineId)` to render per-row
/// spinners, error chips, and "no violations found" placeholders.
enum EngineRunPhase {
  /// Engine has not yet started this run.
  idle,

  /// Subprocess is in flight.
  running,

  /// Subprocess completed normally; violations (if any) are already
  /// in the violation store.
  completed,

  /// Subprocess returned an error or threw mid-run. [EngineRunStatus.error]
  /// carries the diagnostic message.
  failed,

  /// Engine binary was not found / could not be invoked. Distinct from
  /// [failed] because the appropriate UI affordance is "install /
  /// configure this engine" rather than "this engine errored out".
  unavailable,

  /// User cancelled the active run.
  cancelled,
}

/// Snapshot of one engine's run status. Immutable.
@immutable
class EngineRunStatus {
  /// Creates an [EngineRunStatus].
  const EngineRunStatus({
    required this.engineId,
    required this.phase,
    this.violationCount = 0,
    this.error,
    this.startedAt,
    this.completedAt,
    this.sourcesUsed,
    this.sourcesTotal,
  });

  /// Convenience: the idle starting state.
  factory EngineRunStatus.idle(String engineId) =>
      EngineRunStatus(engineId: engineId, phase: EngineRunPhase.idle);

  /// The engine this status applies to.
  final String engineId;

  /// Current phase.
  final EngineRunPhase phase;

  /// Number of violations the engine emitted during this run. Updated
  /// live as the engine streams; final on `completed`.
  final int violationCount;

  /// Human-readable error message when [phase] is [EngineRunPhase.failed]
  /// or [EngineRunPhase.unavailable]. English-only — the display layer
  /// wraps it for localization.
  final String? error;

  /// When the engine's subprocess started.
  final DateTime? startedAt;

  /// When the engine's run ended (any terminal phase).
  final DateTime? completedAt;

  /// Mixed-language routing surface.
  ///
  /// Number of project source files actually fed to this engine after
  /// language routing (Verilator skips `.vhd` files, GHDL skips
  /// Verilog, etc.). `null` when the engine ran against every source
  /// file (the common case) or when routing did not apply.
  final int? sourcesUsed;

  /// Total project source files at the time of this run. `null` when
  /// routing did not apply — paired with [sourcesUsed].
  final int? sourcesTotal;

  /// Whether the engine ran against a strict subset of the project's
  /// source files (i.e. routing dropped at least one source).
  bool get ranAgainstSubset =>
      sourcesUsed != null &&
      sourcesTotal != null &&
      sourcesUsed! < sourcesTotal!;

  /// Whether the engine is in any terminal phase.
  bool get isTerminal => switch (phase) {
    EngineRunPhase.idle || EngineRunPhase.running => false,
    EngineRunPhase.completed ||
    EngineRunPhase.failed ||
    EngineRunPhase.unavailable ||
    EngineRunPhase.cancelled => true,
  };

  /// Returns a copy with overridden fields.
  EngineRunStatus copyWith({
    EngineRunPhase? phase,
    int? violationCount,
    String? error,
    DateTime? startedAt,
    DateTime? completedAt,
    int? sourcesUsed,
    int? sourcesTotal,
  }) {
    return EngineRunStatus(
      engineId: engineId,
      phase: phase ?? this.phase,
      violationCount: violationCount ?? this.violationCount,
      error: error ?? this.error,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      sourcesUsed: sourcesUsed ?? this.sourcesUsed,
      sourcesTotal: sourcesTotal ?? this.sourcesTotal,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! EngineRunStatus) return false;
    return other.engineId == engineId &&
        other.phase == phase &&
        other.violationCount == violationCount &&
        other.error == error &&
        other.startedAt == startedAt &&
        other.completedAt == completedAt &&
        other.sourcesUsed == sourcesUsed &&
        other.sourcesTotal == sourcesTotal;
  }

  @override
  int get hashCode => Object.hash(
    engineId,
    phase,
    violationCount,
    error,
    startedAt,
    completedAt,
    sourcesUsed,
    sourcesTotal,
  );

  @override
  String toString() =>
      'EngineRunStatus($engineId, $phase, $violationCount violations'
      '${error != null ? ', error: $error' : ''})';
}
