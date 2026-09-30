// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/interfaces/baseline_store.dart';
import 'package:lintcrux/services/baseline/noop_baseline_store.dart';

/// Riverpod provider exposing the app-wide [BaselineStore].
///
/// The default is a [NoopBaselineStore]: the baseline & delta workflow is a
/// Pro feature, and nothing in the open core reads this provider.
///
/// The Pro overlay binds it per tab to `JsonFileBaselineStore` (reading and
/// writing `<project-root>/.lintcrux-baseline.json`), and its readers — the
/// status chip, the baseline toolbar, the comparison screen, the snapshot
/// behind `currentBaselineSnapshotProvider` — are all overlay code.
final Provider<BaselineStore> baselineStoreProvider = Provider<BaselineStore>((
  ref,
) {
  final store = NoopBaselineStore();
  ref.onDispose(store.dispose);
  return store;
});
