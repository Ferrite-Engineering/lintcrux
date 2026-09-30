// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/transformers/severity_override_transformer.dart';

Violation _v(String rule, Severity sev) => Violation(
  engineId: 'verilator',
  ruleId: 'verilator/$rule',
  severity: sev,
  message: 'msg',
  location: const SourceLocation(file: '/a.sv', line: 1, column: 1),
);

void main() {
  group('SeverityOverrideTransformer', () {
    test('returns the input unchanged when no override is configured', () {
      const t = SeverityOverrideTransformer.empty;
      final v = _v('UNUSED', Severity.warning);
      expect(t.transform(v), same(v));
    });

    test('does not touch violations whose ruleId is not in the map', () {
      const t = SeverityOverrideTransformer(<String, Severity>{
        'verilator/WIDTH': Severity.error,
      });
      final v = _v('UNUSED', Severity.warning);
      expect(t.transform(v).severity, Severity.warning);
    });

    test('promotes warning to error and preserves the original in raw', () {
      const t = SeverityOverrideTransformer(<String, Severity>{
        'verilator/UNUSED': Severity.error,
      });
      final v = _v('UNUSED', Severity.warning);
      final out = t.transform(v);
      expect(out.severity, Severity.error);
      expect(out.raw['lintcrux.engineSeverity'], 'warning');
    });

    test('demotes warning to note', () {
      const t = SeverityOverrideTransformer(<String, Severity>{
        'verilator/UNUSED': Severity.note,
      });
      final v = _v('UNUSED', Severity.warning);
      expect(t.transform(v).severity, Severity.note);
    });

    test('mapping to the same severity is a no-op (no raw mutation)', () {
      const t = SeverityOverrideTransformer(<String, Severity>{
        'verilator/UNUSED': Severity.warning,
      });
      final v = _v('UNUSED', Severity.warning);
      expect(
        t.transform(v).raw.containsKey('lintcrux.engineSeverity'),
        isFalse,
      );
    });

    test('preserves all other fields exactly', () {
      const t = SeverityOverrideTransformer(<String, Severity>{
        'verilator/UNUSED': Severity.error,
      });
      final v = _v('UNUSED', Severity.warning);
      final out = t.transform(v);
      expect(out.engineId, v.engineId);
      expect(out.ruleId, v.ruleId);
      expect(out.message, v.message);
      expect(out.location, v.location);
    });
  });
}
