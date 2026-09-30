// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async' show unawaited;

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/app_settings.dart';
import 'package:lintcrux/services/persistence/recent_projects_settings_codec.dart';

/// The [SettingsService] that reads and writes the Recent projects list.
///
/// Override in tests with a `SettingsService(codec, prefsOverride: prefs)`
/// so the round trip runs against `SharedPreferences.setMockInitialValues`.
final Provider<SettingsService<List<String>>>
recentProjectsSettingsServiceProvider = Provider<SettingsService<List<String>>>(
  (_) => const SettingsService<List<String>>(RecentProjectsSettingsCodec()),
  name: 'recentProjectsSettingsServiceProvider',
);

/// Recent project file paths surfaced on the welcome screen, most recent
/// first. Backed by [recentProjectsListProvider]; a plain [Provider] so a
/// test can hand the welcome screen a fixed list with `overrideWithValue`.
final Provider<List<String>> recentProjectsProvider = Provider<List<String>>(
  (ref) => ref.watch(recentProjectsListProvider),
  name: 'recentProjectsProvider',
);

/// Owns the persisted Recent projects list.
final NotifierProvider<RecentProjectsNotifier, List<String>>
recentProjectsListProvider =
    NotifierProvider<RecentProjectsNotifier, List<String>>(
      RecentProjectsNotifier.new,
      name: 'recentProjectsListProvider',
    );

/// Notifier backing [recentProjectsListProvider].
///
/// `build()` returns an empty list and overlays the stored list when it
/// arrives — the welcome screen renders immediately either way. Every
/// project that opens is recorded by [markOpened] (`OpenProjectInWorkspace`
/// calls it), moved to the front, and the list is capped at
/// [AppSettings.maxRecentProjects].
class RecentProjectsNotifier extends Notifier<List<String>> {
  /// Set once the list changes at run time, so the asynchronous restore
  /// merges into what landed first instead of replacing it.
  bool _touched = false;

  /// Set once the stored list has been read. Until then nothing is saved: a
  /// project opened before the read finished (the usual case when tabs are
  /// restored at launch, since the welcome screen that would read the list
  /// first is never built) used to save a one-entry list over the stored
  /// history, which the restore then declined to touch.
  bool _restored = false;

  /// Paths removed at run time before the stored list arrived, so the merge
  /// does not bring them back.
  final Set<String> _removed = <String>{};

  @override
  List<String> build() {
    unawaited(_restore());
    return const <String>[];
  }

  Future<void> _restore() async {
    var stored = const <String>[];
    try {
      stored = await ref.read(recentProjectsSettingsServiceProvider).load();
    } on Object {
      // No preferences backend (a pure-Dart host, a missing plugin): the
      // list simply starts empty.
    }
    if (!ref.mounted) return;
    _restored = true;
    if (!_touched) {
      state = List<String>.unmodifiable(
        stored.take(AppSettings.maxRecentProjects),
      );
      return;
    }
    // Opens and removals that landed first go in front of the stored
    // history, not instead of it.
    _set(
      <String>[
        ...state,
        for (final path in stored)
          if (!state.contains(path) && !_removed.contains(path)) path,
      ].take(AppSettings.maxRecentProjects).toList(growable: false),
    );
  }

  /// Records that the project at [path] was opened: moves it to the front
  /// and persists the list.
  void markOpened(String path) {
    _touched = true;
    _removed.remove(path);
    final next = <String>[
      path,
      for (final existing in state)
        if (existing != path) existing,
    ].take(AppSettings.maxRecentProjects).toList(growable: false);
    _set(next);
  }

  /// Removes [path], for an entry whose file no longer opens.
  void remove(String path) {
    if (!state.contains(path) && _restored) return;
    _touched = true;
    _removed.add(path);
    _set(<String>[
      for (final existing in state)
        if (existing != path) existing,
    ]);
  }

  void _set(List<String> next) {
    state = List<String>.unmodifiable(next);
    if (_restored) unawaited(_persist(state));
  }

  Future<void> _persist(List<String> paths) async {
    try {
      await ref.read(recentProjectsSettingsServiceProvider).save(paths);
    } on Object {
      // No preferences backend: the list still works for this session.
    }
  }
}
