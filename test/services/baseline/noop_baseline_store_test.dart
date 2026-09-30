// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/interfaces/baseline_store.dart';
import 'package:lintcrux/domain/models/lint_baseline.dart';
import 'package:lintcrux/services/baseline/baseline_store_provider.dart';
import 'package:lintcrux/services/baseline/noop_baseline_store.dart';

void main() {
  group('NoopBaselineStore', () {
    test('activeBaseline() returns null', () async {
      final store = NoopBaselineStore();
      addTearDown(store.dispose);
      expect(await store.activeBaseline(), isNull);
    });

    test('setBaseline() throws UnsupportedError', () async {
      final store = NoopBaselineStore();
      addTearDown(store.dispose);
      final b = LintBaseline(
        baselineId: 'b-1',
        createdAt: DateTime.utc(2026, 5, 25),
        projectPath: '/p',
        frozenViolations: const [],
      );
      await expectLater(
        () => store.setBaseline(b),
        throwsUnsupportedError,
      );
    });

    test('clearBaseline() is an idempotent no-op (does not throw)', () async {
      final store = NoopBaselineStore();
      addTearDown(store.dispose);
      // The contract says clearing on a permanently-empty store is a
      // no-op; defensive callers can call it without guard.
      await store.clearBaseline();
      await store.clearBaseline();
    });

    test('watch() returns a closeable broadcast stream', () async {
      final store = NoopBaselineStore();
      // Subscribe; verify no synchronous emissions and that dispose
      // closes the underlying stream.
      final sub = store.watch().listen((_) {
        fail('NoopBaselineStore should not emit any events');
      });
      await Future<void>.delayed(const Duration(milliseconds: 1));
      await sub.cancel();
      await store.dispose();
    });
  });

  group('baselineStoreProvider (open-core binding)', () {
    test('default binding is a NoopBaselineStore', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(baselineStoreProvider);
      expect(store, isA<NoopBaselineStore>());
    });

    test('Pro overlay-style override surfaces a non-noop store', () async {
      final fake = _FakeStore();
      final container = ProviderContainer(
        overrides: [
          baselineStoreProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);
      final store = container.read(baselineStoreProvider);
      expect(store, same(fake));
      expect(await store.activeBaseline(), isNotNull);
    });
  });
}

/// Minimal in-memory fake to verify the provider override surface.
class _FakeStore implements BaselineStore {
  LintBaseline? _b = LintBaseline(
    baselineId: 'fake',
    createdAt: DateTime.utc(2026, 5, 25),
    projectPath: '/p',
    frozenViolations: const [],
  );

  @override
  Future<LintBaseline?> activeBaseline() async => _b;

  @override
  Future<void> setBaseline(LintBaseline baseline) async {
    _b = baseline;
  }

  @override
  Future<void> clearBaseline() async {
    _b = null;
  }

  @override
  Stream<LintBaseline?> watch() => const Stream<LintBaseline?>.empty();
}
