// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/waiver.dart';

void main() {
  final createdAt = DateTime.utc(2026, 5, 22, 10);

  group('Waiver', () {
    test('required fields produce a usable waiver with sensible defaults', () {
      final w = Waiver(
        id: 'w-1',
        ruleId: 'verilator/UNUSEDSIGNAL',
        filePath: '/tmp/x.v',
        reason: 'legacy code',
        author: 'mfink',
        createdAt: createdAt,
      );
      expect(w.lineStart, isNull);
      expect(w.lineEnd, isNull);
      expect(w.expiresAt, isNull);
    });

    test('copyWith updates fields without disturbing others', () {
      final w = Waiver(
        id: 'w-1',
        ruleId: 'verilator/UNUSEDSIGNAL',
        filePath: '/tmp/x.v',
        reason: 'legacy code',
        author: 'mfink',
        createdAt: createdAt,
      );
      final later = createdAt.add(const Duration(days: 30));
      final next = w.copyWith(expiresAt: later);
      expect(next.expiresAt, later);
      expect(next.reason, 'legacy code');
    });

    test('== treats matching content as equal', () {
      final a = Waiver(
        id: 'w-1',
        ruleId: 'v/X',
        filePath: '/x.v',
        reason: 'r',
        author: 'a',
        createdAt: createdAt,
      );
      final b = Waiver(
        id: 'w-1',
        ruleId: 'v/X',
        filePath: '/x.v',
        reason: 'r',
        author: 'a',
        createdAt: createdAt,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
