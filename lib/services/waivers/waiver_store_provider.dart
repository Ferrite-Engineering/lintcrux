// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_projects/crux_projects.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderFamily;
import 'package:lintcrux/domain/interfaces/waiver_store.dart';
import 'package:lintcrux/services/waivers/noop_waiver_store.dart';

/// Internal per-project family providing one [WaiverStore] per active
/// project id.
///
/// The real state owner for the per-project waiver store. The Pro overlay
/// overrides the wrapper [waiverStoreProvider]; the open-core build keys
/// one [NoopWaiverStore] per project so two open projects never share a
/// store instance under split-pane / many-tabs.
final ProviderFamily<WaiverStore, String> waiverStorePerProjectFamily =
    Provider.family<WaiverStore, String>(
      (ref, projectId) {
        final store = NoopWaiverStore();
        ref.onDispose(store.dispose);
        return store;
      },
      name: 'waiverStorePerProject',
    );

/// Riverpod provider exposing the active [WaiverStore].
///
/// Open-core binding returns a [NoopWaiverStore] — the managed waiver
/// system is a Pro feature, and the open-core
/// build honors only inline source pragmas via the
/// [PragmaWaiverTransformer].
///
/// Lifted to [perProjectScope] so each open project owns
/// its own waiver store instance and switching the active project retains
/// each project's state. The Pro overlay overrides this provider with
/// `JsonFileWaiverStore` in its `proOverrides` list (the override replaces
/// this wrapper and resolves the Pro store for the active project) —
/// consumers read the provider unconditionally.
final Provider<WaiverStore> waiverStoreProvider = perProjectScope<WaiverStore>(
  'waiver_store',
  (ref, projectId) => ref.watch(waiverStorePerProjectFamily(projectId)),
);
