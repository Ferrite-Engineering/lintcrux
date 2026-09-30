// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/interfaces/lint_run_cache_service.dart';
import 'package:lintcrux/domain/models/lint_cache_entry.dart';
import 'package:lintcrux/domain/models/lint_cache_invalidation_event.dart';
import 'package:lintcrux/domain/models/lint_cache_key.dart';
import 'package:lintcrux/domain/models/lint_cache_stats.dart';

void main() {
  group('NoopLintRunCacheService', () {
    const svc = NoopLintRunCacheService();
    final key = LintCacheKey(
      engineId: 'verilator',
      sourceFingerprint: 'a' * 64,
      configFingerprint: 'b' * 64,
      engineVersion: '5.026',
    );

    test('lookup always returns null', () async {
      expect(await svc.lookup(key), isNull);
    });

    test('store is a silent no-op', () async {
      final entry = LintCacheEntry(
        key: key,
        violations: const [],
        createdAt: DateTime.utc(2026, 5, 25),
        lastAccessedAt: DateTime.utc(2026, 5, 25),
        runDurationMs: 100,
        filePath: '/a/b.sv',
      );
      // No throw, no observable side effect.
      await svc.store(entry);
      expect(await svc.lookup(key), isNull);
    });

    test('invalidate is a silent no-op', () async {
      await svc.invalidate(
        LintCacheInvalidationManualClear(
          occurredAt: DateTime.utc(2026, 5, 25),
          reason: 'test',
          entriesRemoved: 0,
        ),
      );
    });

    test('stats returns LintCacheStats.empty', () async {
      expect(await svc.stats(), equals(LintCacheStats.empty));
    });

    test('clearAll is a silent no-op', () async {
      await svc.clearAll();
    });

    test('invalidations stream is empty (no events)', () async {
      final events = await svc.invalidations.toList();
      expect(events, isEmpty);
    });
  });
}
