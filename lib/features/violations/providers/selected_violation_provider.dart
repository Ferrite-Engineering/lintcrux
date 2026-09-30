// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/services/rules/rule_database_provider.dart';
import 'package:lintcrux/services/telemetry/telemetry_event_catalog.dart';

/// Holds the violation currently focused in the inspector pane.
///
/// The inspector (and the source preview, click-to-source action, and
/// any other surfaces that want to react to a single violation) watch
/// this provider. Selection in the violation table writes to this; the
/// table's multi-select [ViolationTableState.selectedRuleIds] is a
/// separate concept aimed at bulk actions.
///
/// The state holds the violation by value so reruns that produce a
/// fresh-but-equal violation continue to satisfy the selection. When
/// the underlying violation disappears from the visible list (e.g. a
/// filter excludes it), the inspector renders an empty state and the
/// selection auto-clears on the next selection event.
class SelectedViolationNotifier extends Notifier<Violation?> {
  Violation? _pending;

  @override
  Violation? build() {
    // Auto-clear the selection if the visible-set no longer contains it.
    // This keeps the inspector and source preview from rendering stale
    // data after the user changes the filter or sort.
    final visible = ref.watch(visibleViolationsProvider);
    final current = _pending;
    if (current == null) return null;
    if (!visible.contains(current)) return null;
    return current;
  }

  /// Selects [v], replacing any prior selection.
  void select(Violation v) {
    _pending = v;
    state = v;
    _recordRuleDocViewed(v);
  }

  /// Records `rule_doc.viewed` when the newly selected violation's rule has an
  /// entry in the rule database.
  ///
  /// The question it answers is "is the rule database worth extending to all
  /// six engines", so what is counted is a *documented* rule being put on
  /// screen — selecting a violation is what mounts the Inspector's metadata
  /// section, and a selection whose rule the database does not know renders
  /// nothing to view and is not counted.
  ///
  /// **Only the engine is sent.** The rule id is what the database was keyed
  /// on, and the telemetry never-collect list bans rule names paired with
  /// the file they were
  /// found in — which is exactly what this event would be if it carried one.
  /// Engine ids are application vocabulary and are allowed; they still go
  /// through [telemetryEngineToken] so the property stays a closed set.
  ///
  /// Instrumented here rather than in `InspectorPane.build` because a build
  /// runs on every rebuild — a resize would count as a view.
  void _recordRuleDocViewed(Violation v) {
    // `.value`: the database is a small asset load that resolves early;
    // before it does, nothing is on screen to have been viewed.
    final database = ref.read(ruleDatabaseProvider).value;
    if (database == null || database.lookup(v.ruleId) == null) return;
    ref
        .read(telemetryServiceProvider)
        .record(
          TelemetryEvent(
            'rule_doc.viewed',
            properties: <String, Object?>{
              'engine': telemetryEngineToken(v.engineId),
            },
          ),
        );
  }

  /// Clears the selection, restoring the Inspector's engine-status view.
  ///
  /// `_pending` is cleared alongside `state` deliberately — [build] restores
  /// from it whenever the visible set changes, so clearing only the state
  /// would put the selection back on the next filter or sort.
  void clear() {
    _pending = null;
    state = null;
  }
}

/// Riverpod provider for the currently inspected violation.
final NotifierProvider<SelectedViolationNotifier, Violation?>
selectedViolationProvider =
    NotifierProvider<SelectedViolationNotifier, Violation?>(
      SelectedViolationNotifier.new,
    );
