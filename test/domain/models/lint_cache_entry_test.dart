// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/lint_cache_entry.dart';
import 'package:lintcrux/domain/models/lint_cache_key.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';

void main() {
  final key = LintCacheKey(
    engineId: 'verilator',
    sourceFingerprint: 'a' * 64,
    configFingerprint: 'b' * 64,
    engineVersion: '5.026',
  );
  final t = DateTime.utc(2026, 5, 25, 12);

  const violation = Violation(
    engineId: 'verilator',
    ruleId: 'verilator/UNUSED',
    severity: Severity.warning,
    message: 'Signal unused',
    location: SourceLocation(file: '/a/b.sv', line: 10, column: 5),
  );

  LintCacheEntry entry({
    int runDurationMs = 1500,
    String filePath = '/a/b.sv',
    List<Violation>? violations,
    DateTime? lastAccessedAt,
  }) => LintCacheEntry(
    key: key,
    violations: violations ?? [violation],
    createdAt: t,
    lastAccessedAt: lastAccessedAt ?? t,
    runDurationMs: runDurationMs,
    filePath: filePath,
  );

  group('LintCacheEntry', () {
    test('equality is structural across all fields', () {
      expect(entry(), equals(entry()));
      expect(entry().hashCode, equals(entry().hashCode));
    });

    test('copyWith updates lastAccessedAt while preserving rest', () {
      final original = entry();
      final hit = original.copyWith(
        lastAccessedAt: DateTime.utc(2026, 5, 25, 13),
      );
      expect(hit.key, equals(original.key));
      expect(hit.violations, equals(original.violations));
      expect(hit.createdAt, equals(original.createdAt));
      expect(hit.lastAccessedAt, isNot(equals(original.lastAccessedAt)));
      expect(hit.runDurationMs, equals(original.runDurationMs));
      expect(hit.filePath, equals(original.filePath));
    });

    test('differs on runDurationMs', () {
      expect(entry(runDurationMs: 9999), isNot(equals(entry())));
    });

    test('differs on filePath', () {
      expect(entry(filePath: '/x/y.sv'), isNot(equals(entry())));
    });

    test('differs on violations contents', () {
      final other = entry(violations: const []);
      expect(other, isNot(equals(entry())));
    });

    test('empty violations list is a valid entry', () {
      final e = entry(violations: const []);
      expect(e.violations, isEmpty);
      // No assertion failures, no surprises.
      expect(e.runDurationMs, equals(1500));
    });
  });
}
