// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/lint_run_completion_event.dart';

/// Broadcast bus carrying project-wide [LintRunCompletionEvent]s.
///
/// This is the **root** aggregation point that decouples the per-tab
/// run-completion *producers* (the Pro `ProLintRunCompletionDispatcher`,
/// registered per-tab so each tab's dispatcher snapshots its own
/// [ViolationStore]) from the app-wide *consumers* (the trend-store
/// ingestion listener, bookmark stale-detection, Verible auto-run) that
/// subscribe to [lintRunCompletionEventProvider].
///
/// Each tab's dispatcher lives in its own per-tab `ProviderContainer`
/// (see `lintcruxTabOverridesFactory`), but reads *this* provider through
/// the standard parent-container lookup so every tab emits into the one
/// shared root bus. A [StreamProvider] cannot be pushed into from the
/// outside, so this hand-rolled broadcast controller is the seam a
/// per-tab producer writes to and the root [StreamProvider] reads from.
///
/// Mirrors the [LintRunLifecycleBus] shape (see `lint_run_lifecycle.dart`)
/// one layer downstream: the lifecycle bus carries slim run-boundary ticks
/// (per-tab), this bus carries the fully-built completion event (root).
class LintRunCompletionEventBus {
  final StreamController<LintRunCompletionEvent> _controller =
      StreamController<LintRunCompletionEvent>.broadcast();

  /// The completion-event stream. Broadcast — supports many observers.
  Stream<LintRunCompletionEvent> get events => _controller.stream;

  /// Publishes [event] to every subscriber. No-op once [dispose]d.
  void emit(LintRunCompletionEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  /// Closes the underlying controller. Wired to `ref.onDispose`.
  Future<void> dispose() => _controller.close();
}

/// App-wide (root) [LintRunCompletionEventBus].
///
/// Deliberately **not** listed in `lintcruxTabOverridesFactory`: it stays
/// root-scoped so per-tab dispatchers (which resolve it via the parent
/// container) and root-scoped consumers share one instance.
final Provider<LintRunCompletionEventBus> lintRunCompletionEventBusProvider =
    Provider<LintRunCompletionEventBus>((ref) {
      final bus = LintRunCompletionEventBus();
      ref.onDispose(bus.dispose);
      return bus;
    });
