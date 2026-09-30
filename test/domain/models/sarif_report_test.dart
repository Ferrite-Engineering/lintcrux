// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/run.dart';
import 'package:lintcrux/domain/models/sarif_report.dart';

void main() {
  final t0 = DateTime.utc(2026, 5, 22);
  final t1 = t0.add(const Duration(seconds: 1));

  Run emptyRun(String id, String engineId) => Run(
    id: id,
    engineId: engineId,
    engineVersion: '$engineId 0',
    startedAt: t0,
    finishedAt: t1,
    violations: const [],
  );

  group('SarifReport', () {
    test('defaults — SARIF 2.1.0 + the canonical schema URL', () {
      final r = SarifReport(runs: [emptyRun('r1', 'verilator')]);
      expect(r.version, '2.1.0');
      expect(r.schema, 'https://json.schemastore.org/sarif-2.1.0.json');
      expect(r.runs, hasLength(1));
    });

    test('copyWith — replace runs preserves version and schema', () {
      final r = SarifReport(runs: [emptyRun('r1', 'verilator')]);
      final next = r.copyWith(runs: [emptyRun('r2', 'slang')]);
      expect(next.runs.first.engineId, 'slang');
      expect(next.version, r.version);
      expect(next.schema, r.schema);
    });

    test('== treats matching content as equal', () {
      final a = SarifReport(runs: [emptyRun('r1', 'verilator')]);
      final b = SarifReport(runs: [emptyRun('r1', 'verilator')]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('== distinguishes differing run order', () {
      final a = SarifReport(
        runs: [emptyRun('r1', 'verilator'), emptyRun('r2', 'slang')],
      );
      final b = SarifReport(
        runs: [emptyRun('r2', 'slang'), emptyRun('r1', 'verilator')],
      );
      expect(a, isNot(b));
    });
  });
}
