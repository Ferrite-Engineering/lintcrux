// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';

void main() {
  group('Severity', () {
    test('declared order is fatal < error < warning < note < none', () {
      expect(Severity.values, [
        Severity.fatal,
        Severity.error,
        Severity.warning,
        Severity.note,
        Severity.none,
      ]);
    });

    test('severityCompare orders fatal-first', () {
      final list = <Severity>[
        Severity.warning,
        Severity.fatal,
        Severity.note,
        Severity.error,
        Severity.none,
      ]..sort(severityCompare);
      expect(list, [
        Severity.fatal,
        Severity.error,
        Severity.warning,
        Severity.note,
        Severity.none,
      ]);
    });

    test('severityCompare is reflexive and symmetric', () {
      for (final a in Severity.values) {
        expect(severityCompare(a, a), 0);
        for (final b in Severity.values) {
          expect(
            severityCompare(a, b).sign,
            -severityCompare(b, a).sign,
          );
        }
      }
    });
  });
}
