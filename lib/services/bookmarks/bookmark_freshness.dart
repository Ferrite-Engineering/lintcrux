// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/baseline_violation.dart';
import 'package:lintcrux/services/bookmarks/json_file_violation_bookmark_store.dart';
import 'package:lintcrux/services/bookmarks/violation_bookmark_store_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/run/lint_run_lifecycle.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';
import 'package:logging/logging.dart';

/// Id of the most recent lint run completed in this tab, or `null` before
/// the first one.
///
/// A bookmark is *stale* when its `lastSeenRunId` is set and differs from
/// this id: the violation it marks did not fire in the latest run. A
/// bookmark whose `lastSeenRunId` is still `null` has not been matched by
/// any run since it was made, and is not flagged.
///
/// Building the notifier subscribes it to this tab's
/// [lintRunLifecycleBusProvider]. On every `running → idle` transition it
/// fingerprints the tab's unsuppressed violations, records the run against
/// each bookmark they match (`JsonFileViolationBookmarkStore
/// .updateLastSeenForRun`), and publishes the new run id.
///
/// Per tab: `lintcruxTabOverridesFactory` re-binds it, and
/// `ProjectTabContent` holds a subscription for the tab's lifetime so the
/// listener is installed before the first run completes.
final NotifierProvider<BookmarkFreshnessNotifier, String?>
bookmarkFreshnessProvider =
    NotifierProvider<BookmarkFreshnessNotifier, String?>(
      BookmarkFreshnessNotifier.new,
    );

/// State holder behind [bookmarkFreshnessProvider].
class BookmarkFreshnessNotifier extends Notifier<String?> {
  bool _wasRunning = false;
  int _runSeq = 0;

  @override
  String? build() {
    final sub = ref
        .watch(lintRunLifecycleBusProvider)
        .events
        .listen(_onLifecycleEvent);
    ref.onDispose(sub.cancel);
    return null;
  }

  void _onLifecycleEvent(LintRunLifecycleEvent event) {
    final wasRunning = _wasRunning;
    _wasRunning = event.isRunning;
    if (event.isRunning || !wasRunning) return;
    final finishedAt = (event.finishedAt ?? DateTime.now()).toUtc();
    recordRun('run-${finishedAt.microsecondsSinceEpoch}-${_runSeq++}');
  }

  /// Records a completed run with id [runId] against this tab's bookmarks
  /// and publishes it as the latest run. Called on every run completion;
  /// visible for tests so a run can be recorded without driving the
  /// lifecycle bus.
  void recordRun(String runId) {
    final projectRoot = ref.read(currentProjectProvider)?.rootPath;
    final store = ref.read(violationBookmarkStoreProvider);
    if (projectRoot != null && store is JsonFileViolationBookmarkStore) {
      final firing = <String>{
        for (final v in ref.read(violationStoreProvider).all)
          if (!v.isSuppressed)
            baselineFingerprintFor(v, projectRoot: projectRoot),
      };
      // Fire-and-forget, so a failed write (a read-only checkout) has no
      // caller to reach and would surface as an uncaught error after every
      // run. The refreshed freshness still shows; it is just not saved.
      unawaited(
        store
            .updateLastSeenForRun(runId: runId, firingFingerprints: firing)
            .catchError((Object error, StackTrace st) {
              Logger('lintcrux.bookmarks').warning(
                'Could not save which bookmarks run $runId saw to '
                '${store.file.path}',
                error,
                st,
              );
            }),
      );
    }
    state = runId;
  }
}
