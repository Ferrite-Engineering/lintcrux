// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

/// Failure record produced when a tab's `.lintcrux` project file
/// cannot be loaded (file missing, permission denied, schema invalid,
/// malformed YAML, …).
///
/// Carried by [configLoadErrorProvider] and rendered by the project-tab
/// empty state as an actionable error surface rather than a silent
/// no-op or a stale Phase placeholder.
@immutable
class ConfigLoadError {
  /// Creates a [ConfigLoadError].
  const ConfigLoadError({required this.path, required this.reason});

  /// Absolute path of the `.lintcrux` file that failed to load.
  final String path;

  /// English-only diagnostic message from the underlying exception.
  /// The display layer wraps it with localized title / hint chrome
  /// but the reason itself is forwarded verbatim so the user sees
  /// the precise OS error (e.g. "No such file or directory").
  final String reason;

  @override
  bool operator ==(Object other) =>
      other is ConfigLoadError && other.path == path && other.reason == reason;

  @override
  int get hashCode => Object.hash(path, reason);

  @override
  String toString() => 'ConfigLoadError(path: $path, reason: $reason)';
}

/// Per-tab provider holding the most recent [ConfigLoadError] (or
/// `null` when the tab loaded successfully).
///
/// Set by [ConfigLoadErrorNotifier.setError] from
/// `ProjectTabContent._maybeHydrate` after a `ProjectFileException`,
/// and cleared by [ConfigLoadErrorNotifier.clear] when the user
/// retries via File → Open Project or otherwise re-binds the tab.
/// `ProjectTabContent` watches this provider and renders an error
/// empty state instead of the IDE layout when it is non-null.
///
/// Scope: per-tab. Override via
/// `lintcruxTabOverridesFactory` so two tabs each carry their own
/// error state without bleeding through the root container.
final NotifierProvider<ConfigLoadErrorNotifier, ConfigLoadError?>
configLoadErrorProvider =
    NotifierProvider<ConfigLoadErrorNotifier, ConfigLoadError?>(
      ConfigLoadErrorNotifier.new,
    );

/// Notifier exposing `setError` / `clear` over [configLoadErrorProvider].
class ConfigLoadErrorNotifier extends Notifier<ConfigLoadError?> {
  @override
  ConfigLoadError? build() => null;

  /// Set the active load error for this tab.
  ///
  /// Kept as an action verb (not a Dart setter) so call sites read
  /// `notifier.setError(err)` matching `.clear()` and the
  /// `currentProjectProvider.notifier.load(project)` /
  /// `lintRunProvider.notifier.runAll(project)` mutator vocabulary.
  // ignore: use_setters_to_change_properties
  void setError(ConfigLoadError error) {
    state = error;
  }

  /// Clear the active load error for this tab (after a successful
  /// reload or when the user moves on).
  void clear() {
    state = null;
  }
}
