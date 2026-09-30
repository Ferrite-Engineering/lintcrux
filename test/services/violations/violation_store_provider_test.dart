// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/interfaces/violation_store.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';

void main() {
  group('violationStoreProvider', () {
    test('returns the in-memory implementation by default', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(violationStoreProvider);
      expect(store, isA<InMemoryViolationStore>());
      expect(store, isA<ViolationStore>());
    });

    test('returns the same instance across reads', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final a = container.read(violationStoreProvider);
      final b = container.read(violationStoreProvider);
      expect(identical(a, b), isTrue);
    });

    test('can be overridden for tests', () {
      final fake = InMemoryViolationStore();
      addTearDown(fake.dispose);
      final container = ProviderContainer(
        overrides: [
          violationStoreProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);
      expect(identical(container.read(violationStoreProvider), fake), isTrue);
    });
  });
}
