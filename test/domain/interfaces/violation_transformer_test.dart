// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/violation_transformer.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';

class _Tag implements ViolationTransformer {
  _Tag(this.key, this.value);
  final String key;
  final String value;
  @override
  Violation transform(Violation v) =>
      v.copyWith(raw: <String, dynamic>{...v.raw, key: value});
}

class _Promote implements ViolationTransformer {
  const _Promote();
  @override
  Violation transform(Violation v) => v.copyWith(severity: Severity.error);
}

void main() {
  group('CompositeViolationTransformer', () {
    const base = Violation(
      engineId: 'e',
      ruleId: 'e/R',
      severity: Severity.warning,
      message: 'm',
      location: SourceLocation(file: '/a.sv', line: 1, column: 1),
    );

    test('empty composite returns the input unchanged', () {
      expect(
        CompositeViolationTransformer.empty.transform(base),
        base,
      );
    });

    test('single transformer applies once', () {
      const t = CompositeViolationTransformer([_Promote()]);
      expect(t.transform(base).severity, Severity.error);
    });

    test('multiple transformers apply left-to-right', () {
      final t = CompositeViolationTransformer([
        _Tag('first', '1'),
        _Tag('second', '2'),
      ]);
      final out = t.transform(base);
      expect(out.raw['first'], '1');
      expect(out.raw['second'], '2');
    });

    test('the later transformer sees the output of the earlier one', () {
      final t = CompositeViolationTransformer([
        _Tag('marker', 'a'),
        _Tag('marker', 'b'),
      ]);
      expect(t.transform(base).raw['marker'], 'b');
    });
  });
}
