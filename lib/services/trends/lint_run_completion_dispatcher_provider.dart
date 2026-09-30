// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/interfaces/lint_run_completion_dispatcher.dart';

/// Riverpod seam for the per-tab
/// [LintRunCompletionDispatcher].
///
/// Open Core's default is [NoopLintRunCompletionDispatcher]. The Pro
/// overlay registers its `ProLintRunCompletionDispatcher` **per tab**
/// (via `extraTabOverridesProvider`, appended to
/// `lintcruxTabOverridesFactory`) so each tab's dispatcher snapshots that
/// tab's own `violationStoreProvider` on completion — a root-scoped
/// dispatcher reads the empty root store instead (the trend-tracking
/// "records zero data points" defect). The Pro dispatcher observes this
/// tab's `lintRunLifecycleBusProvider`, builds one aggregated
/// [LintRunCompletionEvent] per `running → idle` transition, and emits it
/// into the root `lintRunCompletionEventBusProvider`, which
/// `lintRunCompletionEventProvider` republishes to every consumer.
///
/// Realized by `ProjectTabContent.build`, which `ref.watch`es this
/// provider inside the per-tab container so the dispatcher's `start()`
/// runs (and its lifecycle subscription installs) before any run
/// completes — the per-tab analogue of `_EagerStartupGate`. The
/// dispatcher is a singleton for the lifetime of the per-tab
/// `ProviderContainer`; `ref.onDispose` calls its `stop()`.
final Provider<LintRunCompletionDispatcher>
lintRunCompletionDispatcherProvider = Provider<LintRunCompletionDispatcher>((
  ref,
) {
  final dispatcher = const NoopLintRunCompletionDispatcher()..start();
  ref.onDispose(dispatcher.stop);
  return dispatcher;
});
