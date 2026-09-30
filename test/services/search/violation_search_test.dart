// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/search/violation_search.dart';

Violation _v(String rule, String msg) => Violation(
  engineId: 'verilator',
  ruleId: 'verilator/$rule',
  severity: Severity.warning,
  message: msg,
  location: const SourceLocation(file: '/a.sv', line: 1, column: 1),
);

void main() {
  group('ViolationSearch', () {
    const search = ViolationSearch();

    test('empty query returns no matches', () {
      final out = search.search(
        haystack: [_v('A', 'msg')],
        query: '',
        mode: SearchMode.substring,
      );
      expect(out, isEmpty);
    });

    group('substring mode', () {
      test('matches the rule id (case-insensitive)', () {
        final out = search.search(
          haystack: [_v('UNUSEDSIGNAL', 'msg')],
          query: 'unused',
          mode: SearchMode.substring,
        );
        expect(out, hasLength(1));
        expect(out.single.matchedField, 'rule');
      });

      test('matches the message (case-insensitive)', () {
        final out = search.search(
          haystack: [_v('A', 'Some Foo Bar')],
          query: 'foo',
          mode: SearchMode.substring,
        );
        expect(out, hasLength(1));
        expect(out.single.matchedField, 'message');
      });

      test('rule match wins over message match', () {
        final out = search.search(
          haystack: [_v('FOO', 'with FOO substring')],
          query: 'foo',
          mode: SearchMode.substring,
        );
        expect(out, hasLength(1));
        expect(out.single.matchedField, 'rule');
      });

      test('no matches yields an empty list', () {
        final out = search.search(
          haystack: [_v('A', 'msg')],
          query: 'zzz',
          mode: SearchMode.substring,
        );
        expect(out, isEmpty);
      });
    });

    group('glob mode', () {
      test('* matches any chars', () {
        final out = search.search(
          haystack: [
            _v('UNUSEDSIGNAL', 'msg'),
            _v('USEDSIGNAL', 'msg'),
            _v('WIDTH', 'msg'),
          ],
          query: '*SIGNAL',
          mode: SearchMode.glob,
        );
        expect(out, hasLength(2));
      });

      test('? matches exactly one char', () {
        final out = search.search(
          haystack: [
            _v('AB', 'msg'),
            _v('A', 'msg'),
            _v('ABC', 'msg'),
          ],
          query: 'verilator/A?',
          mode: SearchMode.glob,
        );
        expect(out, hasLength(1));
        expect(out.single.violation.ruleId, 'verilator/AB');
      });

      test('regex metacharacters in the glob are escaped', () {
        final out = search.search(
          haystack: [_v('A.B', 'msg')],
          query: 'verilator/A.B',
          mode: SearchMode.glob,
        );
        expect(out, hasLength(1));
      });
    });

    group('regex mode', () {
      test('plain regex matches', () {
        final out = search.search(
          haystack: [_v('UNUSEDSIGNAL', 'msg')],
          query: 'unused.*signal',
          mode: SearchMode.regex,
        );
        expect(out, hasLength(1));
      });

      test('case-insensitive by default', () {
        final out = search.search(
          haystack: [_v('UNUSEDSIGNAL', 'msg')],
          query: 'UNUSED',
          mode: SearchMode.regex,
        );
        expect(out, hasLength(1));
      });

      test('invalid regex returns no matches (no throw)', () {
        final out = search.search(
          haystack: [_v('A', 'msg')],
          query: '(unbalanced',
          mode: SearchMode.regex,
        );
        expect(out, isEmpty);
      });
    });
  });
}
