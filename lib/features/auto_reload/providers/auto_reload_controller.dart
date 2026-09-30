// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_file_watcher/crux_file_watcher.dart';
import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/features/run/providers/lint_run_notifier.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';

/// Reacts to source-file changes by re-running the engines, honoring
/// the user's [AutoReloadMode] setting.
///
/// - `auto` — re-run the engines whenever a watched source changes
///   (debounced 500 ms by [FileWatcherService] + an extra 50 ms coalesce
///   for cross-file batches).
/// - `prompt` — set [pendingReloadProvider] to `true`; the tab's
///   `AutoReloadHost` shows a "source files changed — re-run?" snackbar.
/// - `off` — no-op (watchers are not even spawned).
///
/// The controller watches [currentProjectProvider] and the mode chosen in
/// Settings > General (`AppSettings.autoReloadMode`); changing either
/// tears the watcher set down and rebuilds it. It is realized per tab by
/// `AutoReloadHost`, which every project tab mounts.
class AutoReloadController extends Notifier<void> {
  final List<FileWatcherService> _watchers = [];
  final List<StreamSubscription<FileWatchEvent>> _subs = [];
  Timer? _debounce;
  // Accumulates the per-source paths whose watcher fired
  // during the current debounce window so `runIncremental` knows which
  // files actually changed (vs `runAll` which re-lints everything).
  final Set<String> _pendingChanged = <String>{};

  @override
  void build() {
    ref.onDispose(_disposeWatchers);
    final project = ref.watch(currentProjectProvider);
    final mode = ref.watch(
      appSettingsProvider.select((s) => s.autoReloadMode),
    );
    _disposeWatchers();
    if (project == null || mode == AutoReloadMode.off) {
      return;
    }
    _spawnWatchers(project, mode);
  }

  void _disposeWatchers() {
    _debounce?.cancel();
    _debounce = null;
    _pendingChanged.clear();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    for (final w in _watchers) {
      w.dispose();
    }
    _watchers.clear();
  }

  void _spawnWatchers(LintProject project, AutoReloadMode mode) {
    final watchFactory = ref.read(autoReloadWatchFactoryProvider);
    for (final src in project.sourceFiles) {
      final watcher = FileWatcherService(watchFactory: watchFactory)
        ..startWatching(src);
      _subs.add(watcher.events.listen(_onChanged(project, mode, src)));
      _watchers.add(watcher);
    }
  }

  void Function(FileWatchEvent) _onChanged(
    LintProject project,
    AutoReloadMode mode,
    String sourcePath,
  ) {
    return (event) {
      _pendingChanged.add(sourcePath);
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 50), () {
        // Snapshot then clear so subsequent fires accumulate
        // independently while the current run is in flight.
        final changed = Set<String>.from(_pendingChanged);
        _pendingChanged.clear();
        switch (mode) {
          case AutoReloadMode.auto:
            // Incremental re-run when every enabled engine supports
            // it; `LintRunNotifier.runIncremental` transparently falls
            // back to `runAll` for non-incremental engine sets.
            unawaited(
              ref
                  .read(lintRunProvider.notifier)
                  .runIncremental(project, changed),
            );
          case AutoReloadMode.prompt:
            ref.read(pendingReloadProvider.notifier).markPending(pending: true);
          case AutoReloadMode.off:
            break;
        }
      });
    };
  }
}

/// Injection seam for [AutoReloadController]'s per-source-file
/// [FileWatcherService] construction. `null` (the default) means
/// "use the real `dart:io` directory watch"; tests override this with
/// a fake [WatchFactory] that emits controlled [FileSystemEvent]s so
/// the debounce / mode-dispatch logic can be exercised without
/// touching the real filesystem.
final Provider<WatchFactory?> autoReloadWatchFactoryProvider =
    Provider<WatchFactory?>((ref) => null);

/// Provider that drives the "source files changed — re-run?" prompt.
/// `true` when at least one source file has changed since the last
/// run AND the user is in `prompt` mode.
final NotifierProvider<PendingReloadNotifier, bool> pendingReloadProvider =
    NotifierProvider<PendingReloadNotifier, bool>(
      PendingReloadNotifier.new,
    );

/// Notifier backing [pendingReloadProvider].
class PendingReloadNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Sets the pending flag; the snackbar's dismiss handler calls
  /// `markPending(pending: false)` after the user resolves it.
  // ignore: use_setters_to_change_properties
  void markPending({required bool pending}) {
    state = pending;
  }
}

/// Provider that activates the [AutoReloadController]. The controller is a
/// `Notifier<void>` — being watched is what spawns the watchers, so it
/// runs only while something watches it: each project tab's
/// `AutoReloadHost`.
final NotifierProvider<AutoReloadController, void>
autoReloadControllerProvider = NotifierProvider<AutoReloadController, void>(
  AutoReloadController.new,
);
