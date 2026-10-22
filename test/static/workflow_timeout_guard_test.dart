// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard: every GitHub Actions job is bounded, and the engine canary
// keeps its own limits.
//
// A hung macOS job once ran for six hours and drained a month's budget, so an
// unbounded job is a defect, not a style choice. The check parses the YAML
// (`package:yaml`); a text search would pass a `timeout-minutes` that sits in a
// comment, in a step's `with:` block, or on the wrong job.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// Job id to its `timeout-minutes` (null when absent) for one workflow.
Map<String, Object?> jobTimeouts(String yamlText) {
  final doc = loadYaml(yamlText);
  if (doc is! YamlMap) return const {};
  final jobs = doc['jobs'];
  if (jobs is! YamlMap) return const {};
  return {
    for (final entry in jobs.entries)
      if (entry.value is YamlMap && (entry.value as YamlMap)['uses'] == null)
        entry.key as String: (entry.value as YamlMap)['timeout-minutes'],
  };
}

bool _isPositive(Object? minutes) => minutes is int && minutes > 0;

bool _isOverCap(Object? minutes) => minutes is int && minutes > 360;

List<File> _workflows() {
  final dir = Directory('.github/workflows');
  if (!dir.existsSync()) fail('missing directory: .github/workflows');
  return dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.yml') || f.path.endsWith('.yaml'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

void main() {
  group('every workflow job is bounded', () {
    test('there are workflows to check', () {
      expect(_workflows(), isNotEmpty);
    });

    for (final file in _workflows()) {
      test(file.path, () {
        final timeouts = jobTimeouts(file.readAsStringSync());
        final unbounded = [
          for (final e in timeouts.entries)
            if (!_isPositive(e.value)) e.key,
        ];
        expect(unbounded, isEmpty, reason: 'jobs without timeout-minutes');
        final long = [
          for (final e in timeouts.entries)
            if (_isOverCap(e.value)) e.key,
        ];
        expect(long, isEmpty, reason: 'timeout-minutes above the 360 cap');
      });
    }
  });

  group('engine-canary.yml', () {
    final file = File('.github/workflows/engine-canary.yml');

    test('exists', () {
      expect(file.existsSync(), isTrue, reason: 'missing engine-canary.yml');
    });

    test('the canary job is capped at 60 minutes', () {
      final timeouts = jobTimeouts(file.readAsStringSync());
      expect(timeouts['cdc'], 60);
    });

    test('runs monthly and on dispatch, on Linux', () {
      final doc = loadYaml(file.readAsStringSync()) as YamlMap;
      final on = doc['on'] as YamlMap;
      expect(on.containsKey('workflow_dispatch'), isTrue);
      expect(on['schedule'] as YamlList, isNotEmpty);
      for (final job in (doc['jobs'] as YamlMap).values) {
        expect((job as YamlMap)['runs-on'], startsWith('ubuntu'));
      }
    });

    test('requires the live toolchain instead of skipping without it', () {
      final text = file.readAsStringSync();
      expect(text, contains('CDC_LIVE_REQUIRED'));
      expect(text, contains('--tags oss-cad-live'));
    });
  });

  group('the checker itself', () {
    test('rejects a job with no timeout-minutes', () {
      const yaml = '''
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
''';
      expect(jobTimeouts(yaml)['a'], isNull);
    });

    test('ignores a timeout that only appears in a comment', () {
      const yaml = '''
jobs:
  a:
    # timeout-minutes: 30
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
''';
      expect(jobTimeouts(yaml)['a'], isNull);
    });

    test('does not credit a step-level timeout to its job', () {
      const yaml = '''
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
        timeout-minutes: 5
''';
      expect(jobTimeouts(yaml)['a'], isNull);
    });

    test('reads a real timeout', () {
      const yaml = '''
jobs:
  a:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - run: echo hi
''';
      expect(jobTimeouts(yaml)['a'], 30);
    });
  });
}
