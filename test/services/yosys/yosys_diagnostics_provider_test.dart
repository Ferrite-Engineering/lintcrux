// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/yosys/yosys_diagnostics_provider.dart';

void main() {
  group('YosysDiagnosticsNotifier', () {
    test('initial state is empty', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(yosysDiagnosticsProvider).diagnostics, isEmpty);
    });

    test('replace stores the supplied list immutably', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      const ds = <YosysDiagnostic>[
        YosysDiagnostic(
          severity: YosysDiagnosticSeverity.warning,
          message: 'Multiply driven net',
        ),
      ];
      c.read(yosysDiagnosticsProvider.notifier).replace(ds);
      final state = c.read(yosysDiagnosticsProvider);
      expect(state.diagnostics, hasLength(1));
      expect(state.diagnostics.first.message, 'Multiply driven net');
      expect(() => state.diagnostics.add(ds.first), throwsUnsupportedError);
    });

    test('clear empties the diagnostics list', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(yosysDiagnosticsProvider.notifier)
        ..replace(const [
          YosysDiagnostic(
            severity: YosysDiagnosticSeverity.warning,
            message: 'x',
          ),
        ])
        ..clear();
      expect(c.read(yosysDiagnosticsProvider).diagnostics, isEmpty);
    });

    test('clear is a no-op when already empty', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final before = c.read(yosysDiagnosticsProvider);
      c.read(yosysDiagnosticsProvider.notifier).clear();
      expect(identical(c.read(yosysDiagnosticsProvider), before), isTrue);
    });

    test('severityCounts buckets per severity', () {
      final state = YosysDiagnosticsState(
        diagnostics: List.unmodifiable(const [
          YosysDiagnostic(
            severity: YosysDiagnosticSeverity.error,
            message: 'e1',
          ),
          YosysDiagnostic(
            severity: YosysDiagnosticSeverity.warning,
            message: 'w1',
          ),
          YosysDiagnostic(
            severity: YosysDiagnosticSeverity.warning,
            message: 'w2',
          ),
        ]),
      );
      expect(state.severityCounts, {
        YosysDiagnosticSeverity.error: 1,
        YosysDiagnosticSeverity.warning: 2,
      });
    });

    test('filtered returns everything when the filter set is empty', () {
      const ds = <YosysDiagnostic>[
        YosysDiagnostic(
          severity: YosysDiagnosticSeverity.error,
          message: 'e',
        ),
        YosysDiagnostic(
          severity: YosysDiagnosticSeverity.warning,
          message: 'w',
        ),
      ];
      const state = YosysDiagnosticsState(diagnostics: ds);
      expect(state.filtered(const {}), ds);
    });

    test('filtered narrows to the supplied severities', () {
      const ds = <YosysDiagnostic>[
        YosysDiagnostic(
          severity: YosysDiagnosticSeverity.error,
          message: 'e',
        ),
        YosysDiagnostic(
          severity: YosysDiagnosticSeverity.warning,
          message: 'w',
        ),
        YosysDiagnostic(
          severity: YosysDiagnosticSeverity.info,
          message: 'i',
        ),
      ];
      const state = YosysDiagnosticsState(diagnostics: ds);
      final out = state.filtered(const {YosysDiagnosticSeverity.warning});
      expect(out, hasLength(1));
      expect(out.first.message, 'w');
    });
  });
}
