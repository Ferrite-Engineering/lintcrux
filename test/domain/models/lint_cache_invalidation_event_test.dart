// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/lint_cache_invalidation_event.dart';

void main() {
  final t = DateTime.utc(2026, 5, 25, 12);

  group('LintCacheInvalidationEvent', () {
    test('FileChanged equality is structural', () {
      final a = LintCacheInvalidationFileChanged(
        occurredAt: t,
        filePath: '/a/b.sv',
        entriesRemoved: 2,
      );
      final b = LintCacheInvalidationFileChanged(
        occurredAt: t,
        filePath: '/a/b.sv',
        entriesRemoved: 2,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));

      final c = LintCacheInvalidationFileChanged(
        occurredAt: t,
        filePath: '/x/y.sv',
        entriesRemoved: 2,
      );
      expect(a, isNot(equals(c)));
    });

    test('ConfigChanged equality is structural', () {
      final a = LintCacheInvalidationConfigChanged(
        occurredAt: t,
        engineId: 'verilator',
        entriesRemoved: 5,
      );
      final b = LintCacheInvalidationConfigChanged(
        occurredAt: t,
        engineId: 'verilator',
        entriesRemoved: 5,
      );
      expect(a, equals(b));
      expect(
        a,
        isNot(
          equals(
            LintCacheInvalidationConfigChanged(
              occurredAt: t,
              engineId: 'verible',
              entriesRemoved: 5,
            ),
          ),
        ),
      );
    });

    test('EngineVersionChanged equality includes old + new versions', () {
      final a = LintCacheInvalidationEngineVersionChanged(
        occurredAt: t,
        engineId: 'verilator',
        oldVersion: '5.026',
        newVersion: '5.027',
        entriesRemoved: 4,
      );
      final b = LintCacheInvalidationEngineVersionChanged(
        occurredAt: t,
        engineId: 'verilator',
        oldVersion: '5.026',
        newVersion: '5.027',
        entriesRemoved: 4,
      );
      expect(a, equals(b));
      expect(
        a,
        isNot(
          equals(
            LintCacheInvalidationEngineVersionChanged(
              occurredAt: t,
              engineId: 'verilator',
              oldVersion: '5.027',
              newVersion: '5.028',
              entriesRemoved: 4,
            ),
          ),
        ),
      );
    });

    test('ManualClear equality includes reason', () {
      final a = LintCacheInvalidationManualClear(
        occurredAt: t,
        reason: 'user_clicked_clear',
        entriesRemoved: 99,
      );
      final b = LintCacheInvalidationManualClear(
        occurredAt: t,
        reason: 'user_clicked_clear',
        entriesRemoved: 99,
      );
      expect(a, equals(b));
      expect(
        a,
        isNot(
          equals(
            LintCacheInvalidationManualClear(
              occurredAt: t,
              reason: 'recents_purge',
              entriesRemoved: 99,
            ),
          ),
        ),
      );
    });

    test('RetentionPrune carries removed-window timestamps', () {
      final oldest = DateTime.utc(2026, 5, 20);
      final newest = DateTime.utc(2026, 5, 24);
      final a = LintCacheInvalidationRetentionPrune(
        occurredAt: t,
        entriesRemoved: 50,
        oldestRemovedAt: oldest,
        newestRemovedAt: newest,
      );
      expect(a.oldestRemovedAt, equals(oldest));
      expect(a.newestRemovedAt, equals(newest));
      final b = LintCacheInvalidationRetentionPrune(
        occurredAt: t,
        entriesRemoved: 50,
        oldestRemovedAt: oldest,
        newestRemovedAt: newest,
      );
      expect(a, equals(b));
    });

    test('different subtypes are never equal', () {
      final fc = LintCacheInvalidationFileChanged(
        occurredAt: t,
        filePath: '/a/b.sv',
        entriesRemoved: 1,
      );
      final cc = LintCacheInvalidationConfigChanged(
        occurredAt: t,
        engineId: 'verilator',
        entriesRemoved: 1,
      );
      expect(fc, isNot(equals(cc)));
    });
  });
}
