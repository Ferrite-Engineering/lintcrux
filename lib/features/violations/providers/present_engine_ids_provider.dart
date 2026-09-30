// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/interfaces/violation_store.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';

/// Sorted list of engine ids that actually appear in the active
/// [ViolationStore]'s loaded report.
///
/// The violation filter-chip strip derives its per-engine chips from this
/// instead of the engine *registry*. Two reasons:
///
///  1. Web-safety. `engineRegistryProvider` eagerly constructs every
///     engine's run-time runner (`YosysRunner`, …), and the runner's
///     executable-name resolution calls `dart:io Platform.operatingSystem`
///     — unsupported on web. A read-only web SARIF viewer that touched the
///     registry red-screened with
///     `Unsupported operation: Platform._operatingSystem`. A read-only
///     viewer must never instantiate engine runners, so the chip strip
///     sources its engine ids from the loaded results instead.
///  2. UX. The results-derived set shows chips only for engines actually
///     present in the loaded report (verilator / verible / slang / …),
///     not every engine LintCrux *could* run.
///
/// Reactive: re-emits whenever the store mutates (a report replaces an
/// engine bucket), mirroring `visibleViolationsProvider`'s subscription to
/// the store event stream. Like that provider it is rebound per tab in
/// `lintcruxTabOverridesFactory` so the subscription binds to the tab's
/// own [violationStoreProvider], not the root store.
class PresentEngineIdsNotifier extends Notifier<List<String>> {
  // Cancelled in `ref.onDispose` and re-subscribed in `build` when the
  // store identity changes; the lint can't see across those boundaries.
  // ignore: cancel_subscriptions
  StreamSubscription<ViolationStoreEvent>? _sub;

  @override
  List<String> build() {
    final store = ref.watch(violationStoreProvider);
    final old = _sub;
    if (old != null) unawaited(old.cancel());
    _sub = store.events.listen((_) => state = _compute(store));
    ref.onDispose(() {
      final sub = _sub;
      if (sub != null) unawaited(sub.cancel());
    });
    return _compute(store);
  }

  static List<String> _compute(ViolationStore store) {
    final ids = store.byEngine.keys.toList()..sort();
    return List<String>.unmodifiable(ids);
  }
}

/// Sorted engine ids present in the active violation store. See
/// [PresentEngineIdsNotifier].
final NotifierProvider<PresentEngineIdsNotifier, List<String>>
presentEngineIdsProvider =
    NotifierProvider<PresentEngineIdsNotifier, List<String>>(
      PresentEngineIdsNotifier.new,
      name: 'presentEngineIds',
    );
