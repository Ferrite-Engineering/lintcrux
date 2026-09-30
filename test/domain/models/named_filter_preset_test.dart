// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/named_filter_preset.dart';

void main() {
  group('NamedFilterPreset', () {
    const a = NamedFilterPreset(name: 'a');
    const b = NamedFilterPreset(name: 'a');

    test('two presets with the same fields are equal', () {
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('a preset with different severities is not equal', () {
      const x = NamedFilterPreset(
        name: 'a',
        severities: {Severity.error},
      );
      expect(x == a, isFalse);
    });

    test('copyWith preserves untouched fields', () {
      const p = NamedFilterPreset(
        name: 'p',
        severities: {Severity.error},
        engineIds: {'verilator'},
        ruleSubstring: 'WIDTH',
        fileGlob: '*.sv',
        showWaived: true,
      );
      final n = p.copyWith(name: 'q');
      expect(n.name, 'q');
      expect(n.severities, p.severities);
      expect(n.engineIds, p.engineIds);
      expect(n.ruleSubstring, p.ruleSubstring);
      expect(n.fileGlob, p.fileGlob);
      expect(n.showWaived, p.showWaived);
    });

    test('toJson round-trips through fromJson', () {
      const p = NamedFilterPreset(
        name: 'WIDTHs only',
        severities: {Severity.warning, Severity.error},
        engineIds: {'verilator', 'verible'},
        ruleSubstring: 'WIDTH',
        fileGlob: '*.sv',
        showWaived: true,
      );
      final json = p.toJson();
      final back = NamedFilterPreset.fromJson(json)!;
      expect(back, equals(p));
    });

    test('fromJson rejects a map with no name', () {
      expect(NamedFilterPreset.fromJson(const {}), isNull);
      expect(NamedFilterPreset.fromJson(const {'name': ''}), isNull);
    });

    test('fromJson silently ignores unknown keys', () {
      final p = NamedFilterPreset.fromJson(const {
        'name': 'p',
        'unknownFutureField': 'whatever',
      });
      expect(p, isNotNull);
      expect(p!.name, 'p');
    });

    test('fromJson silently drops malformed severity strings', () {
      final p = NamedFilterPreset.fromJson(const {
        'name': 'p',
        'severities': ['error', 'not_a_real_severity'],
      });
      expect(p!.severities, {Severity.error});
    });
  });
}
