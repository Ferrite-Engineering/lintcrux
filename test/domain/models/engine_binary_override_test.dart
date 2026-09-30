// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/engine_binary_override.dart';
import 'package:lintcrux/domain/models/engine_config.dart';

void main() {
  group('EngineBinaryOverride', () {
    test('autoDetect default is EngineBinarySource.system with no path', () {
      const o = EngineBinaryOverride.autoDetect;
      expect(o.source, EngineBinarySource.system);
      expect(o.path, isNull);
    });

    test('toEngineBinaryConfig maps system to system config', () {
      const o = EngineBinaryOverride.autoDetect;
      expect(o.toEngineBinaryConfig().source, EngineBinarySource.system);
    });

    test('toEngineBinaryConfig maps bundled to bundled config', () {
      const o = EngineBinaryOverride(source: EngineBinarySource.bundled);
      expect(o.toEngineBinaryConfig().source, EngineBinarySource.bundled);
    });

    test('toEngineBinaryConfig honors a custom path', () {
      const o = EngineBinaryOverride(
        source: EngineBinarySource.custom,
        path: '/opt/verilator/bin/verilator',
      );
      final config = o.toEngineBinaryConfig();
      expect(config.source, EngineBinarySource.custom);
      expect(config.path, '/opt/verilator/bin/verilator');
    });

    test('custom override with null/empty path falls back to system', () {
      const o1 = EngineBinaryOverride(source: EngineBinarySource.custom);
      const o2 = EngineBinaryOverride(
        source: EngineBinarySource.custom,
        path: '',
      );
      expect(o1.toEngineBinaryConfig().source, EngineBinarySource.system);
      expect(o2.toEngineBinaryConfig().source, EngineBinarySource.system);
    });

    test('copyWith swaps source and clears path when leaving custom', () {
      const o = EngineBinaryOverride(
        source: EngineBinarySource.custom,
        path: '/p',
      );
      final next = o.copyWith(source: EngineBinarySource.bundled);
      expect(next.source, EngineBinarySource.bundled);
      expect(next.path, isNull);
    });

    test('copyWith preserves path when staying in custom', () {
      const o = EngineBinaryOverride(
        source: EngineBinarySource.custom,
        path: '/p',
      );
      final next = o.copyWith(source: EngineBinarySource.custom);
      expect(next.path, '/p');
    });

    test('copyWith clearPath drops the path explicitly', () {
      const o = EngineBinaryOverride(
        source: EngineBinarySource.custom,
        path: '/p',
      );
      final next = o.copyWith(clearPath: true);
      expect(next.path, isNull);
    });

    test('equality and hash are value-based', () {
      const a = EngineBinaryOverride(
        source: EngineBinarySource.custom,
        path: '/p',
      );
      const b = EngineBinaryOverride(
        source: EngineBinarySource.custom,
        path: '/p',
      );
      const c = EngineBinaryOverride(
        source: EngineBinarySource.custom,
        path: '/q',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
