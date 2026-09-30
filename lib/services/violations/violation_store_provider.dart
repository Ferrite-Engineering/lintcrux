// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_projects/crux_projects.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderFamily;
import 'package:lintcrux/domain/interfaces/violation_store.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';

/// Internal per-project family providing one [ViolationStore] per
/// active project id.
///
/// This is the real state owner for the per-project violation set.
/// Widget call sites read the wrapper [violationStoreProvider] which
/// resolves the family slot for the currently-active project; tests
/// that need to seed or inspect a specific project's store reach
/// into this family directly.
///
/// Each per-project store is constructed lazily on first read and
/// disposed when its `ref.onDispose` fires (the wrapper keeps the
/// instance alive while the project is active; switching away keeps
/// the cached instance in the family until the project is dropped
/// from `recentProjects`).
///
/// Mirrors SimCrux's per-project family pattern
/// (`simcrux/lib/services/result_store/per_project_result_store.dart`).
final ProviderFamily<ViolationStore, String> violationStorePerProjectFamily =
    Provider.family<ViolationStore, String>(
      (ref, projectId) {
        final store = InMemoryViolationStore();
        ref.onDispose(store.dispose);
        return store;
      },
      name: 'violationStorePerProject',
    );

/// Riverpod provider exposing the active [ViolationStore].
///
/// The provider is scoped per project via [perProjectScope]. Under the
/// open-core [NoopProjectRegistry] (single-project mode) the behavior is
/// identical to a singleton — one project active at a time means one
/// [InMemoryViolationStore] instance in the family cache. Under the Pro
/// overlay's [JsonFileProjectRegistry] (multi-project mode), each open project
/// owns its own violation set, so opening file `tb_a.v` in project A and
/// `tb_b.v` in project B keeps both projects' violations separated; switching
/// the active project tab swaps the visible store without losing either
/// project's state.
///
/// Per-project semantics are mandatory for the violations store
/// because the violations panel renders the active project's run
/// output — sharing a single store across projects would render
/// project A's defects while the user is looking at project B.
final Provider<ViolationStore> violationStoreProvider =
    perProjectScope<ViolationStore>(
      'violation_store',
      (ref, projectId) => ref.watch(violationStorePerProjectFamily(projectId)),
    );
