// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/models/lint_run_completion_event.dart';

/// Aggregates per-engine completion signals into project-wide
/// [LintRunCompletionEvent]s and pushes them through to consumers
/// (the violation trend store ingestion listener, Pro telemetry
/// surfaces, future audit log feeds).
///
/// The open-core lint runner emits per-engine `RunCompleted` events
/// through the violation store's event stream; that granularity is
/// too fine for trend tracking (we want "the user pressed Run Lint
/// and every engine has finished" — one event per click). The
/// dispatcher is the seam that bridges per-engine completion to
/// project-wide completion.
///
/// Lifecycle:
///   - One dispatcher per tab. `ProjectTabContent` watches
///     `lintRunCompletionDispatcherProvider` in the tab's own container, so
///     `start()` installs its listeners before any of that tab's runs
///     complete.
///   - On every full run completion the dispatcher emits the aggregated
///     event into the root `lintRunCompletionEventBusProvider`.
///   - `stop()` cleans up subscriptions on dispose.
///
/// Open Core ships [NoopLintRunCompletionDispatcher] (does nothing —
/// the seam is testable without the Pro overlay). The Pro overlay
/// supplies a concrete dispatcher that observes
/// `lintRunProvider` + the violation store events, waits for the
/// final per-engine `RunCompleted` to land, builds the project-wide
/// snapshot, and dispatches it to the trend store.
abstract class LintRunCompletionDispatcher {
  /// Begin observing run-completion signals. Idempotent —
  /// implementations should guard against repeated calls.
  void start();

  /// Stop observing and release any held subscriptions.
  void stop();
}

/// Default open-core dispatcher that does nothing. Each tab realizes the
/// seam when its content mounts, so the Pro overlay's per-tab dispatcher is
/// installed before the tab's first run; the open-core build realizes this
/// no-op.
class NoopLintRunCompletionDispatcher implements LintRunCompletionDispatcher {
  /// Creates a [NoopLintRunCompletionDispatcher].
  const NoopLintRunCompletionDispatcher();

  @override
  void start() {}

  @override
  void stop() {}
}
