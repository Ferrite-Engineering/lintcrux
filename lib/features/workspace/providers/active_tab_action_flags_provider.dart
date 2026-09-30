// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/run/providers/lint_run_notifier.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/workspace/tab_container_manager_holder.dart';

/// Root-scope mirror of the **active tab's** per-tab gating flags consumed by
/// `LintcruxActionContext`.
///
/// The action-discovery surfaces (menu bar, command palette, toolbar) and the
/// keyboard dispatch path evaluate enablement at the root scope and cannot
/// `ref.watch` a tab container's providers, so this re-emits the active tab's
/// project / run / violation / selection state up to the root. Mirrors
/// NetCrux's provider of the same name.
@immutable
class ActiveTabActionFlags {
  /// Creates a flags snapshot. Defaults describe an empty tab.
  const ActiveTabActionFlags({
    this.hasProject = false,
    this.runInProgress = false,
    this.hasViolations = false,
    this.hasSelectedViolation = false,
  });

  /// Whether the active tab has a loaded project / config.
  final bool hasProject;

  /// Whether a lint run is executing in the active tab.
  final bool runInProgress;

  /// Whether the active tab's filtered violation list is non-empty.
  final bool hasViolations;

  /// Whether a violation row is selected in the active tab.
  final bool hasSelectedViolation;

  /// Returns a copy with the given fields replaced.
  ActiveTabActionFlags copyWith({
    bool? hasProject,
    bool? runInProgress,
    bool? hasViolations,
    bool? hasSelectedViolation,
  }) => ActiveTabActionFlags(
    hasProject: hasProject ?? this.hasProject,
    runInProgress: runInProgress ?? this.runInProgress,
    hasViolations: hasViolations ?? this.hasViolations,
    hasSelectedViolation: hasSelectedViolation ?? this.hasSelectedViolation,
  );

  @override
  bool operator ==(Object other) =>
      other is ActiveTabActionFlags &&
      other.hasProject == hasProject &&
      other.runInProgress == runInProgress &&
      other.hasViolations == hasViolations &&
      other.hasSelectedViolation == hasSelectedViolation;

  @override
  int get hashCode => Object.hash(
    hasProject,
    runInProgress,
    hasViolations,
    hasSelectedViolation,
  );
}

/// See [ActiveTabActionFlags].
final activeTabActionFlagsProvider =
    NotifierProvider<ActiveTabActionFlagsNotifier, ActiveTabActionFlags>(
      ActiveTabActionFlagsNotifier.new,
      name: 'activeTabActionFlagsProvider',
    );

/// Rebinds to the active tab's container whenever the active tab changes,
/// subscribing to each mirrored per-tab provider and re-emitting its gating
/// projection.
class ActiveTabActionFlagsNotifier extends Notifier<ActiveTabActionFlags> {
  /// True once disposed (or between rebuilds), so a deferred [_apply]
  /// microtask never writes `state` on a dead notifier.
  bool _disposed = false;

  /// Applies [update] to the *current* [state] on a microtask rather than
  /// synchronously.
  ///
  /// The mirrored providers are `container.listen`ed and one can notify while
  /// the widget tree is mid-build — writing `state` there throws "Tried to
  /// modify a provider while the widget tree was building". Applying to the
  /// live `state` (not a value captured at listen time) keeps a batch of
  /// listeners firing in one tick from clobbering one another.
  void _apply(ActiveTabActionFlags Function(ActiveTabActionFlags) update) {
    scheduleMicrotask(() {
      if (_disposed) return;
      final next = update(state);
      if (next != state) state = next;
    });
  }

  @override
  ActiveTabActionFlags build() {
    // build() re-runs on the same instance when its dependencies change; the
    // previous run's onDispose has already flipped this true, so clear it.
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    final activeTabId = ref.watch(
      workspaceProvider.select((ws) => ws.value?.activeTabId),
    );
    final manager = ref.watch(tabContainerManagerHolderProvider).manager;
    if (activeTabId == null || manager == null) {
      return const ActiveTabActionFlags();
    }
    final container = manager.containerFor(activeTabId);

    final subs = <ProviderSubscription<Object?>>[
      container.listen<LintProject?>(
        currentProjectProvider,
        (_, next) => _apply((s) => s.copyWith(hasProject: next != null)),
      ),
      container.listen<LintRunState>(
        lintRunProvider,
        (_, next) => _apply((s) => s.copyWith(runInProgress: next.isRunning)),
      ),
      container.listen<List<Violation>>(
        visibleViolationsProvider,
        (_, next) => _apply((s) => s.copyWith(hasViolations: next.isNotEmpty)),
      ),
      container.listen<Violation?>(
        selectedViolationProvider,
        (_, next) =>
            _apply((s) => s.copyWith(hasSelectedViolation: next != null)),
      ),
    ];
    for (final sub in subs) {
      ref.onDispose(sub.close);
    }

    return ActiveTabActionFlags(
      hasProject: container.read(currentProjectProvider) != null,
      runInProgress: container.read(lintRunProvider).isRunning,
      hasViolations: container.read(visibleViolationsProvider).isNotEmpty,
      hasSelectedViolation: container.read(selectedViolationProvider) != null,
    );
  }
}
