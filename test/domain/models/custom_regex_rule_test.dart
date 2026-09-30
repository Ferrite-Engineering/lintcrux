// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/custom_regex_rule.dart';

void main() {
  group('CustomRegexRule', () {
    test('default patternKind is sourceText and default enabled is true', () {
      const r = CustomRegexRule(
        id: 'no-todo',
        severity: Severity.warning,
        pattern: 'TODO',
        messageTemplate: 'TODO comment found',
      );
      expect(r.patternKind, CustomRulePatternKind.sourceText);
      expect(r.enabled, isTrue);
      expect(r.filePathGlob, isNull);
    });

    test('value equality and hashCode', () {
      const a = CustomRegexRule(
        id: 'r',
        severity: Severity.error,
        pattern: r'\bdefparam\b',
        patternKind: CustomRulePatternKind.identifier,
        messageTemplate: 'defparam is forbidden',
        filePathGlob: '**/*.sv',
        enabled: false,
      );
      const b = CustomRegexRule(
        id: 'r',
        severity: Severity.error,
        pattern: r'\bdefparam\b',
        patternKind: CustomRulePatternKind.identifier,
        messageTemplate: 'defparam is forbidden',
        filePathGlob: '**/*.sv',
        enabled: false,
      );
      const c = CustomRegexRule(
        id: 'r',
        severity: Severity.error,
        pattern: r'\bdefparam\b',
        patternKind: CustomRulePatternKind.identifier,
        // different template
        messageTemplate: 'defparam is forbidden!',
        filePathGlob: '**/*.sv',
        enabled: false,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('copyWith overrides only the specified fields', () {
      const original = CustomRegexRule(
        id: 'r',
        severity: Severity.warning,
        pattern: 'TODO',
        messageTemplate: 'todo found',
      );
      final disabled = original.copyWith(enabled: false);
      expect(disabled.enabled, isFalse);
      expect(disabled.id, original.id);
      expect(disabled.pattern, original.pattern);
    });

    test('toString surfaces id, severity, kind, glob, enabled', () {
      const r = CustomRegexRule(
        id: 'r',
        severity: Severity.warning,
        pattern: 'TODO',
        messageTemplate: 'todo found',
        filePathGlob: '**/*.sv',
        enabled: false,
      );
      final s = r.toString();
      expect(s, contains('id: r'));
      expect(s, contains('severity: Severity.warning'));
      expect(s, contains('kind: CustomRulePatternKind.sourceText'));
      expect(s, contains('glob: **/*.sv'));
      expect(s, contains('enabled: false'));
    });
  });
}
