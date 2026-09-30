// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'engine_corpus_support.dart';

/// Golden-snapshot test for the engine-output parser corpus.
///
/// Discovers every committed `output.txt` under
/// `test/fixtures/engines/<engine>/{generated,captured}/<case>/`, resolves
/// the parser by engine id, runs it over the canned output, and asserts the
/// emitted SARIF equals the sibling `expected.sarif.json`. This pins *our
/// parsing of engine output* (the unified SARIF) against a reviewed golden,
/// so a parser regression — a dropped continuation, a mis-mapped severity,
/// a silently-swallowed unrecognized line — fails loudly.
///
/// Regenerate the goldens after an intentional parser change with:
///
///   REGENERATE=1 flutter test test/services/engines/engine_golden_test.dart
///
/// (or `dart run tool/generate_engine_corpus.dart`, which also refreshes the
/// `verification/` mirror).
void main() {
  const fixturesRoot = 'test/fixtures/engines';
  final regenerate = Platform.environment['REGENERATE'] == '1';

  final root = Directory(fixturesRoot);
  final cases =
      (root.existsSync()
            ? root
                  .listSync(recursive: true)
                  .whereType<File>()
                  .where(
                    (f) =>
                        f.path.endsWith('${Platform.pathSeparator}output.txt'),
                  )
                  .toList()
            : <File>[])
        ..sort((a, b) => a.path.compareTo(b.path));

  test('engine corpus is non-empty (every engine ships at least one case)', () {
    expect(
      cases,
      isNotEmpty,
      reason:
          'No output.txt fixtures found under $fixturesRoot — run '
          '`dart run tool/generate_engine_corpus.dart`.',
    );
    // Every covered hand-rolled parser has at least one generated case.
    final coveredEngines = cases
        .map((f) => _segments(f.path))
        .map((s) => s.engineId)
        .toSet();
    for (final engineId in kCorpusEngineIds) {
      expect(
        coveredEngines,
        contains(engineId),
        reason: 'engine "$engineId" has no corpus case',
      );
    }
  });

  for (final outputFile in cases) {
    final seg = _segments(outputFile.path);
    final goldenFile = File(
      '${outputFile.parent.path}${Platform.pathSeparator}expected.sarif.json',
    );

    test('golden: ${seg.engineId}/${seg.kind}/${seg.caseName}', () {
      final lines = const LineSplitter().convert(
        outputFile.readAsStringSync(),
      );
      final actual = buildCorpusSarifMap(seg.engineId, seg.caseName, lines);

      if (regenerate) {
        const encoder = JsonEncoder.withIndent('  ');
        goldenFile.writeAsStringSync('${encoder.convert(actual)}\n');
        return;
      }

      expect(
        goldenFile.existsSync(),
        isTrue,
        reason:
            'Missing golden ${goldenFile.path} — run '
            '`REGENERATE=1 flutter test '
            'test/services/engines/engine_golden_test.dart`.',
      );
      final expected =
          jsonDecode(goldenFile.readAsStringSync()) as Map<String, dynamic>;
      expect(
        actual,
        expected,
        reason:
            'Parsed SARIF for ${seg.engineId}/${seg.caseName} drifted '
            'from its golden. If this is an intentional parser change, run '
            '`REGENERATE=1 flutter test '
            'test/services/engines/engine_golden_test.dart`.',
      );
    });
  }
}

/// Path segments of a fixture `output.txt`:
/// `…/engines/<engineId>/<kind>/<caseName>/output.txt`.
({String engineId, String kind, String caseName}) _segments(String path) {
  final parts = path.split(Platform.pathSeparator);
  // parts: [..., 'engines', engineId, kind, caseName, 'output.txt']
  final caseName = parts[parts.length - 2];
  final kind = parts[parts.length - 3];
  final engineId = parts[parts.length - 4];
  return (engineId: engineId, kind: kind, caseName: caseName);
}
