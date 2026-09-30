// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

/// Sidecar store for the raw [YosysDiagnostic] records the
/// `YosysCheckEngine` produces during a run.
///
/// The engine already converts each diagnostic into a unified
/// [Violation] for the main violation table; this provider keeps the
/// *structured originals* around so the Tab Diagnostics drawer can
/// surface them in a dedicated "Yosys Diagnostics" section with the
/// raw severity / file:line / message untouched by the violation
/// adapter's coercions (e.g. the kebab-case rule-id heuristic).
///
/// State is per-run and replaces on each completion — the drawer
/// always shows the most recent run's diagnostics. Empty on first
/// launch and after a run that produced no Yosys output.
class YosysDiagnosticsNotifier extends Notifier<YosysDiagnosticsState> {
  @override
  YosysDiagnosticsState build() => const YosysDiagnosticsState();

  /// Replace the entire diagnostics list. Called by the run notifier
  /// when the Yosys engine's stderr has been parsed.
  void replace(List<YosysDiagnostic> diagnostics) {
    state = YosysDiagnosticsState(
      diagnostics: List<YosysDiagnostic>.unmodifiable(diagnostics),
    );
  }

  /// Empty the diagnostics list (e.g. when starting a new run before
  /// Yosys produces its output).
  void clear() {
    if (state.diagnostics.isEmpty) return;
    state = const YosysDiagnosticsState();
  }
}

/// Immutable snapshot of the most recent Yosys diagnostics output.
@immutable
class YosysDiagnosticsState {
  /// Creates a [YosysDiagnosticsState].
  const YosysDiagnosticsState({
    this.diagnostics = const <YosysDiagnostic>[],
  });

  /// All Yosys diagnostics from the most recent run. Order matches
  /// the engine's emission order (typically file order).
  final List<YosysDiagnostic> diagnostics;

  /// Convenience: per-severity counts. Empty when [diagnostics] is.
  Map<YosysDiagnosticSeverity, int> get severityCounts {
    final out = <YosysDiagnosticSeverity, int>{};
    for (final d in diagnostics) {
      out[d.severity] = (out[d.severity] ?? 0) + 1;
    }
    return out;
  }

  /// Returns the subset of diagnostics whose severity is in
  /// [allowedSeverities]. When the set is empty, returns every
  /// diagnostic (used by the drawer's filter-chip wiring where "no
  /// chips selected" means "show all").
  List<YosysDiagnostic> filtered(
    Set<YosysDiagnosticSeverity> allowedSeverities,
  ) {
    if (allowedSeverities.isEmpty) return diagnostics;
    return diagnostics
        .where((d) => allowedSeverities.contains(d.severity))
        .toList(growable: false);
  }
}

/// Riverpod provider exposing the [YosysDiagnosticsNotifier].
final NotifierProvider<YosysDiagnosticsNotifier, YosysDiagnosticsState>
yosysDiagnosticsProvider =
    NotifierProvider<YosysDiagnosticsNotifier, YosysDiagnosticsState>(
      YosysDiagnosticsNotifier.new,
    );
