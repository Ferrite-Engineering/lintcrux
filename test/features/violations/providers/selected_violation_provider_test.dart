// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';

Violation _make(String rule, String file, int line) => Violation(
  engineId: 'verilator',
  ruleId: 'verilator/$rule',
  severity: Severity.warning,
  message: 'msg',
  location: SourceLocation(file: file, line: line, column: 1),
);

void main() {
  group('selectedViolationProvider', () {
    test('starts null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(selectedViolationProvider), isNull);
    });

    test('select() sets the provider value', () {
      final store = InMemoryViolationStore();
      addTearDown(store.dispose);
      final v = _make('R', '/a.sv', 1);
      store.replaceFromEngine('verilator', [v]);
      final container = ProviderContainer(
        overrides: [
          violationStoreProvider.overrideWith((ref) => store),
        ],
      );
      addTearDown(container.dispose);
      // Force visibleViolationsProvider to materialize so the
      // auto-clear logic sees the selection.
      container.read(visibleViolationsProvider);
      container.read(selectedViolationProvider.notifier).select(v);
      expect(container.read(selectedViolationProvider), v);
    });

    test('clear() resets to null', () {
      final store = InMemoryViolationStore();
      addTearDown(store.dispose);
      final v = _make('R', '/a.sv', 1);
      store.replaceFromEngine('verilator', [v]);
      final container = ProviderContainer(
        overrides: [
          violationStoreProvider.overrideWith((ref) => store),
        ],
      );
      addTearDown(container.dispose);
      container.read(visibleViolationsProvider);
      container.read(selectedViolationProvider.notifier)
        ..select(v)
        ..clear();
      expect(container.read(selectedViolationProvider), isNull);
    });

    test('selection auto-clears when the violation leaves the visible '
        'set (filter excludes it)', () async {
      final store = InMemoryViolationStore();
      addTearDown(store.dispose);
      final a = _make('UNUSED', '/a.sv', 1);
      final b = _make('WIDTH', '/b.sv', 1);
      store.replaceFromEngine('verilator', [a, b]);
      final container = ProviderContainer(
        overrides: [
          violationStoreProvider.overrideWith((ref) => store),
        ],
      );
      addTearDown(container.dispose);
      container.read(visibleViolationsProvider);
      container.read(selectedViolationProvider.notifier).select(a);
      expect(container.read(selectedViolationProvider), a);
      // Filter so only WIDTH matches.
      container
          .read(violationTableStateProvider.notifier)
          .setRuleSubstring('WIDTH');
      // Let the visible set recompute by reading it once.
      container.read(visibleViolationsProvider);
      expect(container.read(selectedViolationProvider), isNull);
    });
  });
}
