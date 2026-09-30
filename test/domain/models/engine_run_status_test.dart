// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/engine_run_status.dart';

void main() {
  group('EngineRunStatus', () {
    test('idle factory sets phase and engineId, violations 0', () {
      final s = EngineRunStatus.idle('verilator');
      expect(s.engineId, 'verilator');
      expect(s.phase, EngineRunPhase.idle);
      expect(s.violationCount, 0);
      expect(s.error, isNull);
      expect(s.startedAt, isNull);
      expect(s.completedAt, isNull);
    });

    test(
      'isTerminal returns true only for completed/failed/unavailable/cancelled',
      () {
        final base = EngineRunStatus.idle('e');
        expect(base.isTerminal, isFalse);
        expect(
          base.copyWith(phase: EngineRunPhase.running).isTerminal,
          isFalse,
        );
        expect(
          base.copyWith(phase: EngineRunPhase.completed).isTerminal,
          isTrue,
        );
        expect(
          base.copyWith(phase: EngineRunPhase.failed).isTerminal,
          isTrue,
        );
        expect(
          base.copyWith(phase: EngineRunPhase.unavailable).isTerminal,
          isTrue,
        );
        expect(
          base.copyWith(phase: EngineRunPhase.cancelled).isTerminal,
          isTrue,
        );
      },
    );

    test('copyWith updates fields without disturbing others', () {
      final base = EngineRunStatus.idle('e');
      final next = base.copyWith(
        phase: EngineRunPhase.running,
        violationCount: 3,
      );
      expect(next.engineId, 'e');
      expect(next.phase, EngineRunPhase.running);
      expect(next.violationCount, 3);
    });

    test('== treats equal field tuples as equal', () {
      final a = EngineRunStatus.idle('e');
      final b = EngineRunStatus.idle('e');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('== distinguishes differing engineId', () {
      expect(EngineRunStatus.idle('a'), isNot(EngineRunStatus.idle('b')));
    });

    test('sourcesUsed / sourcesTotal default to null', () {
      final s = EngineRunStatus.idle('e');
      expect(s.sourcesUsed, isNull);
      expect(s.sourcesTotal, isNull);
      expect(s.ranAgainstSubset, isFalse);
    });

    test('ranAgainstSubset is true when used < total', () {
      final s = EngineRunStatus.idle('e').copyWith(
        sourcesUsed: 3,
        sourcesTotal: 5,
      );
      expect(s.ranAgainstSubset, isTrue);
    });

    test('ranAgainstSubset is false when used equals total', () {
      final s = EngineRunStatus.idle('e').copyWith(
        sourcesUsed: 5,
        sourcesTotal: 5,
      );
      expect(s.ranAgainstSubset, isFalse);
    });

    test('copyWith preserves sourcesUsed / sourcesTotal across updates', () {
      final s = EngineRunStatus.idle('e').copyWith(
        sourcesUsed: 2,
        sourcesTotal: 4,
      );
      final next = s.copyWith(phase: EngineRunPhase.running);
      expect(next.sourcesUsed, 2);
      expect(next.sourcesTotal, 4);
    });

    test('== respects sourcesUsed / sourcesTotal', () {
      final a = EngineRunStatus.idle('e').copyWith(
        sourcesUsed: 2,
        sourcesTotal: 4,
      );
      final b = EngineRunStatus.idle('e').copyWith(
        sourcesUsed: 2,
        sourcesTotal: 4,
      );
      final c = EngineRunStatus.idle('e').copyWith(
        sourcesUsed: 3,
        sourcesTotal: 4,
      );
      expect(a, b);
      expect(a, isNot(c));
    });
  });
}
