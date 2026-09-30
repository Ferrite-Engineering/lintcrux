// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/enums/violation_view_mode.dart';
import 'package:lintcrux/domain/interfaces/violation_store.dart';
import 'package:lintcrux/domain/models/filter_preset.dart';
import 'package:lintcrux/services/filter_presets/filter_preset_overlay.dart';

void main() {
  group('overlayFilterPreset', () {
    final fixedAt = DateTime.utc(2026);

    FilterPreset preset(Map<String, Object?> filterState) {
      return FilterPreset(
        id: 'p',
        name: 'P',
        filterState: filterState,
        createdAt: fixedAt,
        updatedAt: fixedAt,
      );
    }

    test('null preset is identity', () {
      const base = ViolationFilter(
        severities: <Severity>{Severity.warning},
        ruleSubstring: 'X',
      );
      final result = overlayFilterPreset(
        preset: null,
        baseFilter: base,
        baseViewMode: ViolationViewMode.onlyResolved,
      );
      expect(result.effectiveFilter, equals(base));
      expect(result.effectiveViewMode, equals(ViolationViewMode.onlyResolved));
    });

    test('severities: preset alone applies', () {
      final result = overlayFilterPreset(
        preset: preset(const <String, Object?>{
          'severities': ['error'],
        }),
        baseFilter: ViolationFilter.empty,
        baseViewMode: ViolationViewMode.allViolations,
      );
      expect(result.effectiveFilter.severities, equals({Severity.error}));
    });

    test('severities: base alone applies', () {
      final result = overlayFilterPreset(
        preset: preset(const <String, Object?>{}),
        baseFilter: const ViolationFilter(
          severities: <Severity>{Severity.warning},
        ),
        baseViewMode: ViolationViewMode.allViolations,
      );
      expect(result.effectiveFilter.severities, equals({Severity.warning}));
    });

    test('severities: intersection when both restrict', () {
      final result = overlayFilterPreset(
        preset: preset(const <String, Object?>{
          'severities': ['error', 'warning'],
        }),
        baseFilter: const ViolationFilter(
          severities: <Severity>{Severity.warning, Severity.note},
        ),
        baseViewMode: ViolationViewMode.allViolations,
      );
      expect(result.effectiveFilter.severities, equals({Severity.warning}));
    });

    test(
      'severities: disjoint intersection yields empty (matches nothing)',
      () {
        final result = overlayFilterPreset(
          preset: preset(const <String, Object?>{
            'severities': ['error'],
          }),
          baseFilter: const ViolationFilter(
            severities: <Severity>{Severity.note},
          ),
          baseViewMode: ViolationViewMode.allViolations,
        );
        expect(result.effectiveFilter.severities, isNotNull);
        expect(result.effectiveFilter.severities, isEmpty);
      },
    );

    test('engineIds: same intersection semantics', () {
      final result = overlayFilterPreset(
        preset: preset(const <String, Object?>{
          'engineIds': ['verilator', 'verible'],
        }),
        baseFilter: const ViolationFilter(
          engineIds: <String>{'verible', 'slang'},
        ),
        baseViewMode: ViolationViewMode.allViolations,
      );
      expect(result.effectiveFilter.engineIds, equals({'verible'}));
    });

    test('ruleSubstring: preset wins when non-empty', () {
      final result = overlayFilterPreset(
        preset: preset(const <String, Object?>{
          'ruleSubstring': 'UNUSED',
        }),
        baseFilter: const ViolationFilter(ruleSubstring: 'WIDTH'),
        baseViewMode: ViolationViewMode.allViolations,
      );
      expect(result.effectiveFilter.ruleSubstring, equals('UNUSED'));
    });

    test('ruleSubstring: empty preset value falls back to base', () {
      final result = overlayFilterPreset(
        preset: preset(const <String, Object?>{
          'ruleSubstring': '',
        }),
        baseFilter: const ViolationFilter(ruleSubstring: 'WIDTH'),
        baseViewMode: ViolationViewMode.allViolations,
      );
      expect(result.effectiveFilter.ruleSubstring, equals('WIDTH'));
    });

    test('fileGlob: preset wins when non-empty', () {
      final result = overlayFilterPreset(
        preset: preset(const <String, Object?>{
          'fileGlob': 'rtl/**',
        }),
        baseFilter: const ViolationFilter(fileGlob: 'tb/**'),
        baseViewMode: ViolationViewMode.allViolations,
      );
      expect(result.effectiveFilter.fileGlob, equals('rtl/**'));
    });

    test('includeSuppressed: OR semantics', () {
      final result = overlayFilterPreset(
        preset: preset(const <String, Object?>{
          'showWaived': true,
        }),
        baseFilter: ViolationFilter.empty,
        baseViewMode: ViolationViewMode.allViolations,
      );
      expect(result.effectiveFilter.includeSuppressed, isTrue);
    });

    test('viewMode: preset wins when present', () {
      final result = overlayFilterPreset(
        preset: preset(const <String, Object?>{
          'viewMode': 'onlyNew',
        }),
        baseFilter: ViolationFilter.empty,
        baseViewMode: ViolationViewMode.onlyResolved,
      );
      expect(result.effectiveViewMode, equals(ViolationViewMode.onlyNew));
    });

    test('viewMode: base passes through when preset omits it', () {
      final result = overlayFilterPreset(
        preset: preset(const <String, Object?>{}),
        baseFilter: ViolationFilter.empty,
        baseViewMode: ViolationViewMode.onlyResolved,
      );
      expect(result.effectiveViewMode, equals(ViolationViewMode.onlyResolved));
    });

    test('viewMode: invalid preset string is ignored', () {
      final result = overlayFilterPreset(
        preset: preset(const <String, Object?>{
          'viewMode': 'nonsense',
        }),
        baseFilter: ViolationFilter.empty,
        baseViewMode: ViolationViewMode.allViolations,
      );
      expect(result.effectiveViewMode, equals(ViolationViewMode.allViolations));
    });

    test('unknown severity strings are silently dropped', () {
      final result = overlayFilterPreset(
        preset: preset(const <String, Object?>{
          'severities': ['error', 'banana', 'fatal'],
        }),
        baseFilter: ViolationFilter.empty,
        baseViewMode: ViolationViewMode.allViolations,
      );
      expect(
        result.effectiveFilter.severities,
        equals({Severity.error, Severity.fatal}),
      );
    });
  });
}
