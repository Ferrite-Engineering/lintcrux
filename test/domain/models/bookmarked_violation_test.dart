// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/baseline_violation.dart';
import 'package:lintcrux/domain/models/bookmarked_violation.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';

void main() {
  group('BookmarkedViolation', () {
    final fixedCreated = DateTime.utc(2026, 5, 1, 12);
    final fixedUpdated = DateTime.utc(2026, 5, 2, 9);

    Violation buildViolation({
      String ruleId = 'verilator/UNUSED',
      String file = '/proj/a.sv',
      int line = 42,
      String message = 'Signal is unused',
    }) {
      return Violation(
        engineId: 'verilator',
        ruleId: ruleId,
        severity: Severity.warning,
        location: SourceLocation(file: file, line: line, column: 1),
        message: message,
      );
    }

    BookmarkedViolation build({
      String id = 'bm_abc',
      String fingerprint = 'fp_1234',
      String ruleId = 'verilator/UNUSED',
      String filePath = '/proj/a.sv',
      int lineNumber = 42,
      String snippet = 'Signal is unused',
      String? note,
      String? color,
      String? lastSeenRunId,
    }) {
      return BookmarkedViolation(
        id: id,
        fingerprint: fingerprint,
        ruleId: ruleId,
        filePath: filePath,
        lineNumber: lineNumber,
        snippet: snippet,
        createdAt: fixedCreated,
        updatedAt: fixedUpdated,
        note: note,
        color: color,
        lastSeenRunId: lastSeenRunId,
      );
    }

    test('round-trips through JSON with all optional fields', () {
      final original = build(
        note: 'Fix me before v2.1',
        color: '#FF0000',
        lastSeenRunId: 'run-1716200000000',
      );
      final json = original.toJson();
      final decoded = BookmarkedViolation.fromJson(
        Map<String, dynamic>.from(json),
      );
      expect(decoded, equals(original));
    });

    test('round-trips through JSON with no optional fields', () {
      final original = build();
      final json = original.toJson();
      expect(json.containsKey('note'), isFalse);
      expect(json.containsKey('color'), isFalse);
      expect(json.containsKey('lastSeenRunId'), isFalse);
      final decoded = BookmarkedViolation.fromJson(
        Map<String, dynamic>.from(json),
      );
      expect(decoded.note, isNull);
      expect(decoded.color, isNull);
      expect(decoded.lastSeenRunId, isNull);
    });

    test('rejects unknown schema version', () {
      final original = build();
      final json = Map<String, dynamic>.from(original.toJson());
      json['version'] = 999;
      expect(
        () => BookmarkedViolation.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects negative line number', () {
      final original = build();
      final json = Map<String, dynamic>.from(original.toJson());
      json['lineNumber'] = -1;
      expect(
        () => BookmarkedViolation.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'fromViolation computes same fingerprint as BaselineViolation',
      () {
        final v = buildViolation();
        final bookmark = BookmarkedViolation.fromViolation(
          id: 'bm_1',
          violation: v,
          createdAt: fixedCreated,
          projectRoot: '/proj',
        );
        final baseline = BaselineViolation.fromViolation(
          v,
          projectRoot: '/proj',
        );
        expect(bookmark.fingerprint, equals(baseline.fingerprint));
      },
    );

    test(
      'fingerprint stability: same violation produces same fingerprint',
      () {
        final v = buildViolation();
        final fp1 = BookmarkedViolation.fromViolation(
          id: 'bm_1',
          violation: v,
          createdAt: fixedCreated,
          projectRoot: '/proj',
        ).fingerprint;
        final fp2 = BookmarkedViolation.fromViolation(
          id: 'bm_2',
          violation: v,
          createdAt: fixedUpdated,
          projectRoot: '/proj',
        ).fingerprint;
        expect(fp1, equals(fp2));
      },
    );

    test(
      'fingerprint changes when ruleId / file / message change',
      () {
        final v1 = buildViolation();
        final v2 = buildViolation(ruleId: 'verilator/WIDTH');
        final v3 = buildViolation(file: '/proj/b.sv');
        final v4 = buildViolation(message: 'A different message');
        final fp1 = BookmarkedViolation.fromViolation(
          id: 'x',
          violation: v1,
          createdAt: fixedCreated,
          projectRoot: '/proj',
        ).fingerprint;
        final fp2 = BookmarkedViolation.fromViolation(
          id: 'x',
          violation: v2,
          createdAt: fixedCreated,
          projectRoot: '/proj',
        ).fingerprint;
        final fp3 = BookmarkedViolation.fromViolation(
          id: 'x',
          violation: v3,
          createdAt: fixedCreated,
          projectRoot: '/proj',
        ).fingerprint;
        final fp4 = BookmarkedViolation.fromViolation(
          id: 'x',
          violation: v4,
          createdAt: fixedCreated,
          projectRoot: '/proj',
        ).fingerprint;
        expect(fp1, isNot(equals(fp2)));
        expect(fp1, isNot(equals(fp3)));
        expect(fp1, isNot(equals(fp4)));
      },
    );

    test(
      'fingerprint stable across line shifts (line is NOT in hash)',
      () {
        final v1 = buildViolation();
        final v2 = buildViolation(line: 100);
        final fp1 = BookmarkedViolation.fromViolation(
          id: 'x',
          violation: v1,
          createdAt: fixedCreated,
          projectRoot: '/proj',
        ).fingerprint;
        final fp2 = BookmarkedViolation.fromViolation(
          id: 'x',
          violation: v2,
          createdAt: fixedCreated,
          projectRoot: '/proj',
        ).fingerprint;
        expect(fp1, equals(fp2));
      },
    );

    test('a version 1 bookmark is read and upgraded against the root', () {
      final v = buildViolation();
      final legacyJson =
          Map<String, dynamic>.from(
              BookmarkedViolation.fromViolation(
                id: 'bm_1',
                violation: v,
                createdAt: fixedCreated,
                projectRoot: '/proj',
              ).toJson(),
            )
            ..['version'] = BookmarkedViolation.absolutePathVersion
            ..['fingerprint'] = BaselineFingerprint.compute(
              ruleId: v.ruleId,
              filePath: v.location.file,
              message: v.message,
            );
      final legacy = BookmarkedViolation.fromJson(legacyJson);
      expect(legacy.version, BookmarkedViolation.absolutePathVersion);

      final upgraded = legacy.withProjectFingerprint('/proj');
      expect(upgraded.version, BookmarkedViolation.currentVersion);
      expect(
        upgraded.fingerprint,
        BaselineViolation.fromViolation(v, projectRoot: '/proj').fingerprint,
      );
      expect(upgraded.withProjectFingerprint('/other'), same(upgraded));
    });

    test('copyWith with clear flags drops optional fields', () {
      final original = build(
        note: 'Old note',
        color: '#FF0000',
        lastSeenRunId: 'run-1',
      );
      final copy = original.copyWith(
        clearNote: true,
        clearColor: true,
        clearLastSeenRunId: true,
      );
      expect(copy.note, isNull);
      expect(copy.color, isNull);
      expect(copy.lastSeenRunId, isNull);
      // Other fields preserved.
      expect(copy.id, equals(original.id));
      expect(copy.fingerprint, equals(original.fingerprint));
    });

    test('copyWith updates the lastSeenRunId for stale detection', () {
      final original = build();
      final updated = original.copyWith(lastSeenRunId: 'run-2');
      expect(updated.lastSeenRunId, equals('run-2'));
      // updatedAt is preserved — stale detection should not touch it.
      expect(updated.updatedAt, equals(original.updatedAt));
    });

    test('equality is value-based', () {
      final a = build(note: 'x');
      final b = build(note: 'x');
      final c = build(note: 'y');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
