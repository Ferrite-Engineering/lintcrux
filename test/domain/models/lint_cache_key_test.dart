// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/lint_cache_key.dart';

void main() {
  group('LintCacheKey', () {
    final defaultSourceFp = 'a' * 64;
    final defaultConfigFp = 'b' * 64;
    LintCacheKey key({
      String engineId = 'verilator',
      String? sourceFingerprint,
      String? configFingerprint,
      String engineVersion = '5.026',
    }) => LintCacheKey(
      engineId: engineId,
      sourceFingerprint: sourceFingerprint ?? defaultSourceFp,
      configFingerprint: configFingerprint ?? defaultConfigFp,
      engineVersion: engineVersion,
    );

    test('equality is structural across all four fields', () {
      expect(key(), equals(key()));
      expect(key().hashCode, equals(key().hashCode));
    });

    test('differs on engineId', () {
      expect(key(engineId: 'verible'), isNot(equals(key())));
    });

    test('differs on sourceFingerprint', () {
      expect(key(sourceFingerprint: 'c' * 64), isNot(equals(key())));
    });

    test('differs on configFingerprint', () {
      expect(key(configFingerprint: 'c' * 64), isNot(equals(key())));
    });

    test('differs on engineVersion', () {
      expect(key(engineVersion: '5.027'), isNot(equals(key())));
    });

    test('toString redacts fingerprints to 8 chars + ellipsis', () {
      final s = key().toString();
      expect(s, contains('verilator'));
      expect(s, contains('${'a' * 8}…'));
      expect(s, contains('${'b' * 8}…'));
      expect(s, contains('5.026'));
    });

    test('rejects empty engineId via assert', () {
      expect(
        () => LintCacheKey(
          engineId: '',
          sourceFingerprint: 'a' * 64,
          configFingerprint: 'b' * 64,
          engineVersion: '5.026',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects empty sourceFingerprint via assert', () {
      expect(
        () => LintCacheKey(
          engineId: 'verilator',
          sourceFingerprint: '',
          configFingerprint: 'b' * 64,
          engineVersion: '5.026',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects empty configFingerprint via assert', () {
      expect(
        () => LintCacheKey(
          engineId: 'verilator',
          sourceFingerprint: 'a' * 64,
          configFingerprint: '',
          engineVersion: '5.026',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects empty engineVersion via assert', () {
      expect(
        () => LintCacheKey(
          engineId: 'verilator',
          sourceFingerprint: 'a' * 64,
          configFingerprint: 'b' * 64,
          engineVersion: '',
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
