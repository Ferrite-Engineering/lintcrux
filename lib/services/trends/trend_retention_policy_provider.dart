// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/trend_retention_policy.dart';

/// Active retention policy for the violation trend store.
///
/// Open-core default is [TrendRetentionPolicy.proDefault] (90 days,
/// 1000 runs, oldest-first pruning). The Pro overlay can override
/// this provider with a user-configured policy from the Settings →
/// Trends section. The open-core default is still meaningful: if a
/// test instantiates the noop store and calls `applyRetention`, it
/// gets the sensible default rather than `null` semantics.
final Provider<TrendRetentionPolicy> trendRetentionPolicyProvider =
    Provider<TrendRetentionPolicy>(
      (_) => TrendRetentionPolicy.proDefault,
    );
