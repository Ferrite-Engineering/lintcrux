// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/verible_availability_status.dart';
import 'package:lintcrux/domain/interfaces/verible_fix_service.dart';
import 'package:lintcrux/domain/models/verible_fix_batch.dart';

void main() {
  group('NoopVeribleFixService', () {
    const svc = NoopVeribleFixService();

    test('checkAvailability returns notInstalled with hint', () async {
      final a = await svc.checkAvailability();
      expect(a.status, VeribleAvailabilityStatus.notInstalled);
      expect(a.missingHint, contains('chipsalliance/verible'));
      expect(a.binaryPath, isNull);
      expect(a.version, isNull);
      expect(a.capabilities, isEmpty);
    });

    test('dryRun returns an empty batch', () async {
      final batch = await svc.dryRun();
      expect(batch.proposals, isEmpty);
      expect(batch.dryRunOnly, isTrue);
      expect(batch.sourceProject, '');
    });

    test('dryRun ignores scopeFilter / specificRules', () async {
      final batch = await svc.dryRun(
        scopeFilter: '/some/path',
        specificRules: ['verible/r1'],
      );
      expect(batch.proposals, isEmpty);
    });

    test('apply returns an empty result list', () async {
      final batch = VeribleFixBatch(
        batchId: 'b1',
        generatedAt: DateTime.utc(2026),
        sourceProject: '/p',
        proposals: const [],
      );
      final results = await svc.apply(batch, const ['p1']);
      expect(results, isEmpty);
    });
  });
}
