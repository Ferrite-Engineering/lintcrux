// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:lintcrux/features/workspace/providers/recent_lists.dart';

/// A [CruxRecentStore] that keeps its entries in memory, so a test seeds the
/// Recent projects list and reads back what was saved without preferences.
class InMemoryRecentStore implements CruxRecentStore {
  /// Creates a store holding [initial].
  InMemoryRecentStore([List<String> initial = const <String>[]])
    : saved = List<String>.of(initial);

  /// What was last saved (or the seed).
  List<String> saved;

  @override
  Future<List<String>> load() async => List<String>.unmodifiable(saved);

  @override
  Future<void> save(List<String> entries) async {
    saved = List<String>.of(entries);
  }
}

/// Seeds the Recent projects list with [initial], held in [store] when given.
Override recentProjectsSeed([
  List<String> initial = const <String>[],
  InMemoryRecentStore? store,
]) => recentProjects.storeProvider.overrideWithValue(
  store ?? InMemoryRecentStore(initial),
);

/// Makes every Recent projects entry present (or [exists] decide), whatever
/// is on disk.
Override recentProjectsExist([bool Function(String path)? exists]) =>
    recentProjects.existsProvider.overrideWithValue(exists ?? (_) => true);
