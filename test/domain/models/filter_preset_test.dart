// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/filter_preset.dart';

void main() {
  group('FilterPreset', () {
    final fixedCreated = DateTime.utc(2026, 5, 1, 12);
    final fixedUpdated = DateTime.utc(2026, 5, 2, 9);

    FilterPreset build({
      String id = 'preset_abc',
      String name = 'My Preset',
      String? description,
      bool builtin = false,
      Map<String, Object?> filterState = const <String, Object?>{},
      int sortOrder = 100,
    }) {
      return FilterPreset(
        id: id,
        name: name,
        description: description,
        builtin: builtin,
        filterState: filterState,
        createdAt: fixedCreated,
        updatedAt: fixedUpdated,
        sortOrder: sortOrder,
      );
    }

    test('round-trips through JSON', () {
      final original = build(
        id: 'preset_xyz',
        name: 'Custom',
        description: 'A user preset',
        filterState: const <String, Object?>{
          'severities': ['error', 'fatal'],
          'engineIds': ['verilator'],
          'ruleSubstring': 'UNUSED',
          'fileGlob': 'rtl/**',
          'showWaived': true,
          'viewMode': 'onlyNew',
        },
        sortOrder: 250,
      );
      final json = original.toJson();
      final decoded = FilterPreset.fromJson(Map<String, dynamic>.from(json));
      expect(decoded, equals(original));
    });

    test('builtin flag survives round-trip', () {
      final original = build(builtin: true, id: 'builtin_all');
      final decoded = FilterPreset.fromJson(
        Map<String, dynamic>.from(original.toJson()),
      );
      expect(decoded.builtin, isTrue);
      expect(decoded.id, equals('builtin_all'));
    });

    test('rejects unknown schema version', () {
      final original = build();
      final json = Map<String, dynamic>.from(original.toJson());
      json['version'] = 999;
      expect(
        () => FilterPreset.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects missing version field', () {
      final original = build();
      final json = Map<String, dynamic>.from(original.toJson())
        ..remove('version');
      expect(
        () => FilterPreset.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects empty id', () {
      final original = build();
      final json = Map<String, dynamic>.from(original.toJson());
      json['id'] = '';
      expect(
        () => FilterPreset.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('copyWith preserves unrelated fields', () {
      final original = build();
      final copy = original.copyWith(name: 'Renamed');
      expect(copy.name, equals('Renamed'));
      expect(copy.id, equals(original.id));
      expect(copy.filterState, equals(original.filterState));
      expect(copy.createdAt, equals(original.createdAt));
    });

    test('equality includes filterState', () {
      final a = build(
        filterState: const <String, Object?>{
          'severities': ['error'],
        },
      );
      final b = build(
        filterState: const <String, Object?>{
          'severities': ['error'],
        },
      );
      final c = build(
        filterState: const <String, Object?>{
          'severities': ['warning'],
        },
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('toJson key order is deterministic for clean diffs', () {
      final preset = build(
        description: 'desc',
        filterState: const <String, Object?>{
          'severities': ['error'],
        },
      );
      final json = preset.toJson();
      expect(
        json.keys.toList(),
        equals(<String>[
          'version',
          'id',
          'name',
          'description',
          'builtin',
          'filterState',
          'createdAt',
          'updatedAt',
          'sortOrder',
        ]),
      );
    });
  });
}
