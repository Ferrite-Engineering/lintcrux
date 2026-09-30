// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/lint_run_completion_event.dart';
import 'package:lintcrux/services/trends/lint_run_completion_event_bus.dart';

/// Stream of project-wide [LintRunCompletionEvent]s — one per completed
/// lint run.
///
/// Reads the root [lintRunCompletionEventBusProvider]. Nothing in the open
/// core reads this provider or emits into that bus: the producer and every
/// consumer are Pro overlay code. The overlay registers a per-tab
/// `ProLintRunCompletionDispatcher` (via the tab-overrides seam) that, on
/// each `running → idle` transition, snapshots the completing tab's
/// [ViolationStore] and emits the aggregated event into the shared root
/// bus — which this provider then republishes to every consumer.
///
/// Consumers (the trend-store ingestion listener, bookmark stale
/// detection, Verible auto-run) subscribe to this stream and react to each
/// completion. Because the producers are per-tab but this provider is
/// root-scoped, a run completed in any tab reaches every consumer through
/// the one bus.
final StreamProvider<LintRunCompletionEvent> lintRunCompletionEventProvider =
    StreamProvider<LintRunCompletionEvent>(
      (ref) => ref.watch(lintRunCompletionEventBusProvider).events,
    );
