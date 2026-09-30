// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/transformers/pragma_waiver_transformer.dart';
import 'package:lintcrux/services/waivers/pragma_waiver_reader.dart';

Violation _v({
  String engine = 'verilator',
  String rule = 'UNUSED',
  String file = '/a.sv',
  int line = 5,
}) => Violation(
  engineId: engine,
  ruleId: '$engine/$rule',
  severity: Severity.warning,
  message: 'msg',
  location: SourceLocation(file: file, line: line, column: 1),
);

void main() {
  group('PragmaWaiverTransformer', () {
    test('returns the input unchanged for an empty range map', () {
      const t = PragmaWaiverTransformer.empty;
      final v = _v();
      expect(t.transform(v).suppression, isNull);
    });

    test('marks a violation suppressed when in range', () {
      const t = PragmaWaiverTransformer(
        LineRangeMap([
          PragmaWaiver(
            file: '/a.sv',
            ruleLocalId: 'UNUSED',
            startLine: 1,
            endLine: 10,
          ),
        ]),
      );
      final out = t.transform(_v());
      expect(out.isSuppressed, isTrue);
      expect(out.suppression!.ruleId, 'verilator/UNUSED');
      expect(out.suppression!.filePath, '/a.sv');
      expect(out.suppression!.reason, contains('lint_off'));
      expect(
        out.raw['lintcrux.pragmaWaiverSourceFile'],
        '/a.sv',
      );
      expect(out.raw['lintcrux.pragmaWaiverSourceLine'], 1);
    });

    test('does not suppress violations whose line is outside the range', () {
      const t = PragmaWaiverTransformer(
        LineRangeMap([
          PragmaWaiver(
            file: '/a.sv',
            ruleLocalId: 'UNUSED',
            startLine: 1,
            endLine: 5,
          ),
        ]),
      );
      expect(t.transform(_v(line: 6)).isSuppressed, isFalse);
    });

    test('does not suppress violations from a different file', () {
      const t = PragmaWaiverTransformer(
        LineRangeMap([
          PragmaWaiver(
            file: '/a.sv',
            ruleLocalId: 'UNUSED',
            startLine: 1,
            endLine: 5,
          ),
        ]),
      );
      expect(t.transform(_v(file: '/b.sv', line: 3)).isSuppressed, isFalse);
    });

    test('does not suppress violations from non-verilator engines', () {
      const t = PragmaWaiverTransformer(
        LineRangeMap([
          PragmaWaiver(
            file: '/a.sv',
            ruleLocalId: 'UNUSED',
            startLine: 1,
            endLine: 5,
          ),
        ]),
      );
      expect(
        t.transform(_v(engine: 'verible', line: 3)).isSuppressed,
        isFalse,
      );
    });

    test('preserves severity and other fields exactly', () {
      const t = PragmaWaiverTransformer(
        LineRangeMap([
          PragmaWaiver(
            file: '/a.sv',
            ruleLocalId: 'UNUSED',
            startLine: 1,
            endLine: 5,
          ),
        ]),
      );
      final v = _v(line: 3);
      final out = t.transform(v);
      expect(out.severity, v.severity);
      expect(out.message, v.message);
      expect(out.location, v.location);
    });
  });
}
