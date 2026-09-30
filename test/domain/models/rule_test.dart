// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/rule.dart';

void main() {
  group('Rule', () {
    test('default constructor — empty description and tags, null helpUri', () {
      const rule = Rule(
        id: 'verilator/UNUSEDSIGNAL',
        defaultSeverity: Severity.warning,
      );
      expect(rule.shortDescription, '');
      expect(rule.fullDescription, '');
      expect(rule.helpUri, isNull);
      expect(rule.tags, isEmpty);
    });

    test('copyWith updates fields without disturbing others', () {
      const rule = Rule(
        id: 'verilator/UNUSEDSIGNAL',
        defaultSeverity: Severity.warning,
      );
      final next = rule.copyWith(
        shortDescription: 'unused signal',
        tags: const ['unused', 'synthesis'],
      );
      expect(next.id, 'verilator/UNUSEDSIGNAL');
      expect(next.shortDescription, 'unused signal');
      expect(next.tags, ['unused', 'synthesis']);
      expect(next.defaultSeverity, Severity.warning);
    });

    test('== treats matching content as equal', () {
      final a = Rule(
        id: 'v/X',
        defaultSeverity: Severity.error,
        tags: const ['a', 'b'],
        helpUri: Uri.parse('https://example.com/X'),
      );
      final b = Rule(
        id: 'v/X',
        defaultSeverity: Severity.error,
        tags: const ['a', 'b'],
        helpUri: Uri.parse('https://example.com/X'),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('== distinguishes differing tag order', () {
      const a = Rule(
        id: 'v/X',
        defaultSeverity: Severity.error,
        tags: ['a', 'b'],
      );
      const b = Rule(
        id: 'v/X',
        defaultSeverity: Severity.error,
        tags: ['b', 'a'],
      );
      expect(a, isNot(b));
    });
  });
}
