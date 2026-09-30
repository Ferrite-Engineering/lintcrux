// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

/// A slim, layer-neutral snapshot of the lint-run lifecycle emitted on
/// every `LintRunNotifier` state change.
///
/// Deliberately carries only what a downstream observer needs to detect
/// run boundaries — `isRunning` (to spot the running↔idle transition) and
/// `finishedAt` (the completion timestamp) — rather than the full
/// feature-layer `LintRunState`. Living in `services/` (not `features/`)
/// is what lets a services-layer consumer (e.g. the Pro trend dispatcher)
/// observe run completions without importing the feature provider.
@immutable
class LintRunLifecycleEvent {
  /// Creates a lifecycle event.
  const LintRunLifecycleEvent({required this.isRunning, this.finishedAt});

  /// Whether a lint run is in progress as of this event.
  final bool isRunning;

  /// When the run finished, if this event marks a completion. `null`
  /// while a run is in progress or on the initial idle state.
  final DateTime? finishedAt;
}

/// Broadcast bus carrying [LintRunLifecycleEvent]s.
///
/// The **feature** layer's `LintRunNotifier` [emit]s into it on every
/// state change (a legal `features → services` write); **services**-layer
/// consumers subscribe to [events] (a legal `services → services` read).
/// This is the seam that decouples run-completion observers from the
/// feature-layer run provider — see ARCHITECTURE.md §6.2.
class LintRunLifecycleBus {
  final StreamController<LintRunLifecycleEvent> _controller =
      StreamController<LintRunLifecycleEvent>.broadcast();

  /// The lifecycle event stream. Broadcast — supports many observers.
  Stream<LintRunLifecycleEvent> get events => _controller.stream;

  /// Publishes [event] to every subscriber. No-op once [dispose]d.
  void emit(LintRunLifecycleEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  /// Closes the underlying controller. Wired to `ref.onDispose`.
  Future<void> dispose() => _controller.close();
}

/// App-wide [LintRunLifecycleBus]. Open-core; the feature run notifier
/// emits into it and any services-layer consumer subscribes.
final Provider<LintRunLifecycleBus> lintRunLifecycleBusProvider =
    Provider<LintRunLifecycleBus>((ref) {
      final bus = LintRunLifecycleBus();
      ref.onDispose(bus.dispose);
      return bus;
    });
