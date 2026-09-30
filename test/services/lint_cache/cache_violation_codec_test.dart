// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/lint_cache/cache_violation_codec.dart';

void main() {
  group('CacheViolationCodec', () {
    test('round-trip preserves all wrapper fields', () {
      const violations = [
        Violation(
          engineId: 'verilator',
          ruleId: 'verilator/UNUSEDSIGNAL',
          severity: Severity.warning,
          message: 'Signal unused',
          location: SourceLocation(
            file: '/a.sv',
            line: 12,
            column: 5,
            endLine: 12,
            endColumn: 10,
          ),
          relatedLocations: [
            SourceLocation(file: '/a.sv', line: 8, column: 1),
          ],
        ),
        Violation(
          engineId: 'verible',
          ruleId: 'verible/no-trailing-spaces',
          severity: Severity.note,
          message: 'trailing whitespace',
          location: SourceLocation(file: '/b.sv', line: 1, column: 80),
        ),
      ];

      final encoded = CacheViolationCodec.encode(violations);
      final decoded = CacheViolationCodec.decode(encoded);
      expect(decoded, equals(violations));
    });

    test('raw map is preserved', () {
      const violation = Violation(
        engineId: 'verilator',
        ruleId: 'verilator/X',
        severity: Severity.error,
        message: 'x',
        location: SourceLocation(file: '/c.sv', line: 1, column: 1),
        raw: {'vendor': 'verilator', 'k': 42},
      );

      final decoded = CacheViolationCodec.decode(
        CacheViolationCodec.encode([violation]),
      );
      expect(decoded.single.raw, equals({'vendor': 'verilator', 'k': 42}));
    });

    test('malformed entries are silently dropped', () {
      final decoded = CacheViolationCodec.decode([
        {'engineId': 'verilator'}, // missing required fields
        {
          'engineId': 'verilator',
          'ruleId': 'verilator/A',
          'severity': 'warning',
          'message': 'm',
          'location': {'file': '/a.sv', 'line': 1, 'column': 1},
        },
      ]);
      expect(decoded.length, equals(1));
      expect(decoded.single.ruleId, equals('verilator/A'));
    });

    test('unknown severity name produces a dropped entry', () {
      final decoded = CacheViolationCodec.decode([
        {
          'engineId': 'verilator',
          'ruleId': 'verilator/A',
          'severity': 'cosmic_horror',
          'message': 'm',
          'location': {'file': '/a.sv', 'line': 1, 'column': 1},
        },
      ]);
      expect(decoded, isEmpty);
    });

    test('suppression is intentionally NOT round-tripped', () {
      // The cache stores PRE-transformer engine output; suppression is
      // a post-transformer derivation. Encoding strips it.
      const violation = Violation(
        engineId: 'verilator',
        ruleId: 'verilator/X',
        severity: Severity.warning,
        message: 'x',
        location: SourceLocation(file: '/a.sv', line: 1, column: 1),
      );
      final encoded = CacheViolationCodec.encode([violation]);
      expect(encoded.single.containsKey('suppression'), isFalse);
    });

    test('empty list round-trips to empty list', () {
      expect(
        CacheViolationCodec.decode(CacheViolationCodec.encode([])),
        isEmpty,
      );
    });
  });
}
