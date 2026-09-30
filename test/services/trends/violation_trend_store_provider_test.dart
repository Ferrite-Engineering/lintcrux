// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/trend_retention_policy.dart';
import 'package:lintcrux/services/trends/noop_violation_trend_store.dart';
import 'package:lintcrux/services/trends/trend_retention_policy_provider.dart';
import 'package:lintcrux/services/trends/violation_trend_store_provider.dart';

void main() {
  group('violationTrendStoreProvider', () {
    test('default returns a NoopViolationTrendStore', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(violationTrendStoreProvider);
      expect(store, isA<NoopViolationTrendStore>());
    });
  });

  group('trendRetentionPolicyProvider', () {
    test('default is TrendRetentionPolicy.proDefault', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final policy = container.read(trendRetentionPolicyProvider);
      expect(policy, TrendRetentionPolicy.proDefault);
    });
  });
}
