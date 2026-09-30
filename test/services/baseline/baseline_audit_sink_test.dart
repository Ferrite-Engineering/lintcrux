// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/baseline/baseline_audit_sink.dart';

void main() {
  group('BaselineAuditEntry', () {
    test('toJson omits null optionals', () {
      final entry = BaselineAuditEntry(
        timestamp: DateTime.utc(2026, 5, 25, 12, 30),
        action: BaselineAuditAction.cleared,
        projectPath: '/abs/project',
      );
      final json = entry.toJson();
      expect(json['timestamp'], '2026-05-25T12:30:00.000Z');
      expect(json['action'], 'cleared');
      expect(json['projectPath'], '/abs/project');
      expect(json.containsKey('baselineId'), isFalse);
      expect(json.containsKey('previousBaselineId'), isFalse);
      expect(json.containsKey('frozenCount'), isFalse);
      expect(json.containsKey('author'), isFalse);
    });

    test('toJson includes every field when populated (set action)', () {
      final entry = BaselineAuditEntry(
        timestamp: DateTime.utc(2026, 5, 25, 12, 30),
        action: BaselineAuditAction.set,
        projectPath: '/abs/project',
        baselineId: 'b-new',
        previousBaselineId: 'b-prev',
        frozenCount: 42,
        author: 'mfink',
      );
      expect(entry.toJson(), <String, Object?>{
        'timestamp': '2026-05-25T12:30:00.000Z',
        'action': 'set',
        'projectPath': '/abs/project',
        'baselineId': 'b-new',
        'previousBaselineId': 'b-prev',
        'frozenCount': 42,
        'author': 'mfink',
      });
    });
  });

  group('NoopBaselineAuditSink', () {
    test('record() returns without throwing for any entry', () async {
      const sink = NoopBaselineAuditSink();
      final entry = BaselineAuditEntry(
        timestamp: DateTime.utc(2026, 5, 25),
        action: BaselineAuditAction.set,
        projectPath: '/p',
        baselineId: 'b-1',
        frozenCount: 0,
      );
      await sink.record(entry);
      // No assertion beyond "did not throw"; the noop sink is a sink.
    });
  });
}
