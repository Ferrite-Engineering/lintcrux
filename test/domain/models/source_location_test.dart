// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/source_location.dart';

void main() {
  group('SourceLocation', () {
    test('asserts 1-based line and column in debug builds', () {
      expect(
        () => SourceLocation(file: '/x.v', line: 0, column: 1),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => SourceLocation(file: '/x.v', line: 1, column: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('copyWith — single field updates leave others intact', () {
      const base = SourceLocation(file: '/x.v', line: 10, column: 5);
      final next = base.copyWith(line: 20);
      expect(next.file, '/x.v');
      expect(next.line, 20);
      expect(next.column, 5);
    });

    test('== treats matching coordinates as equal', () {
      const a = SourceLocation(file: '/x.v', line: 10, column: 5);
      const b = SourceLocation(file: '/x.v', line: 10, column: 5);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('== distinguishes endLine / endColumn variants', () {
      const a = SourceLocation(file: '/x.v', line: 1, column: 1);
      const b = SourceLocation(
        file: '/x.v',
        line: 1,
        column: 1,
        endLine: 2,
        endColumn: 1,
      );
      expect(a, isNot(b));
    });

    test('toString includes a range when present', () {
      const a = SourceLocation(file: '/x.v', line: 1, column: 1);
      const b = SourceLocation(
        file: '/x.v',
        line: 1,
        column: 1,
        endLine: 2,
        endColumn: 3,
      );
      expect(a.toString(), contains('/x.v:1:1'));
      expect(b.toString(), contains('/x.v:1:1-2:3'));
    });
  });
}
