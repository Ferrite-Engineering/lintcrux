// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/engine_config.dart';

void main() {
  group('EngineBinaryConfig', () {
    test('bundled convenience constructor', () {
      const c = EngineBinaryConfig.bundled();
      expect(c.source, EngineBinarySource.bundled);
      expect(c.path, isNull);
      expect(c.extraArgs, isEmpty);
    });

    test('system convenience constructor', () {
      const c = EngineBinaryConfig.system();
      expect(c.source, EngineBinarySource.system);
      expect(c.path, isNull);
    });

    test('custom requires an explicit path', () {
      expect(
        () => EngineBinaryConfig(source: EngineBinarySource.custom),
        throwsA(isA<AssertionError>()),
      );
    });

    test('custom with path is accepted', () {
      const c = EngineBinaryConfig(
        source: EngineBinarySource.custom,
        path: '/usr/local/bin/verilator',
      );
      expect(c.path, '/usr/local/bin/verilator');
    });

    test('copyWith updates fields without disturbing others', () {
      const c = EngineBinaryConfig.bundled();
      final next = c.copyWith(extraArgs: const ['--Wall']);
      expect(next.source, EngineBinarySource.bundled);
      expect(next.extraArgs, ['--Wall']);
    });

    test('== treats matching content as equal', () {
      const a = EngineBinaryConfig.bundled(extraArgs: ['--Wall']);
      const b = EngineBinaryConfig.bundled(extraArgs: ['--Wall']);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('== distinguishes differing extraArgs order', () {
      const a = EngineBinaryConfig.bundled(
        extraArgs: ['--Wall', '--Wpedantic'],
      );
      const b = EngineBinaryConfig.bundled(
        extraArgs: ['--Wpedantic', '--Wall'],
      );
      expect(a, isNot(b));
    });
  });
}
