// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/interfaces/violation_trend_store.dart';
import 'package:lintcrux/services/trends/noop_violation_trend_store.dart';

/// Riverpod provider exposing the app-wide [ViolationTrendStore].
///
/// Open-core binding returns a [NoopViolationTrendStore] — the trend
/// tracking workflow is a Pro feature. The Pro
/// overlay overrides this provider with `SqliteViolationTrendStore`
/// (persistent at `<appSupportDir>/lintcrux/trends.db`).
final Provider<ViolationTrendStore> violationTrendStoreProvider =
    Provider<ViolationTrendStore>((ref) {
      final store = NoopViolationTrendStore();
      ref.onDispose(store.dispose);
      return store;
    });
