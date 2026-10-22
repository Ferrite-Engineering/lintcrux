// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/baseline_violation.dart';
import 'package:lintcrux/domain/models/lint_baseline.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/baseline/baseline_filter.dart';
import 'package:lintcrux/services/sarif/sarif_file_loader.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';

const _dir = 'verification/fixtures/sarif/flow';
const _root = '/work/design';

/// SARIF produced by the suite's flow writer from real place-and-route
/// reports (see `verification/fixtures/sarif/flow/PROVENANCE.md`). Every
/// expectation here is in `expected.json`, written by hand from the RTL in
/// `path_adder.v` and from the SARIF 2.1.0 meaning of the files (read with
/// `jq`), never from what LintCrux's importer returns.
final Map<String, Object?> _expected =
    jsonDecode(
          File('$_dir/expected.json').readAsStringSync(),
        )
        as Map<String, Object?>;

final List<String> _rtl = File('$_dir/path_adder.v').readAsLinesSync();

String _text(String name) => File('$_dir/$name.sarif.json').readAsStringSync();

/// 1-based line of the one RTL line equal to [exact].
int _lineOf(String exact) {
  final matches = [
    for (var i = 0; i < _rtl.length; i++)
      if (_rtl[i] == exact) i + 1,
  ];
  expect(matches, hasLength(1), reason: exact);
  return matches.single;
}

Future<List<Violation>> _import(String json) async {
  final store = InMemoryViolationStore();
  final loader = SarifFileLoader();
  try {
    final report = await loader.loadFromString(json, store: store);
    return report.runs.single.violations;
  } finally {
    loader.dispose();
    await store.dispose();
  }
}

/// [json] with every number the report carries moved: the same design run
/// again with a different place-and-route result.
String _rerun(String json) => json.replaceAllMapped(
  RegExp('("(?:achievedMhz|delayPs)": )([0-9.]+)'),
  (m) => '${m[1]}${double.parse(m[2]!) + 7}',
);

void main() {
  final cases = (_expected['cases']! as Map<String, Object?>)
      .cast<String, Map<String, Object?>>();
  final engineId = _expected['engine_id']! as String;
  final end = _expected['end_register']! as String;
  final key = _expected['fingerprint_key']! as String;

  group('the fixtures are SARIF 2.1.0 with relative locations', () {
    for (final name in [...cases.keys, 'path_ice40_met', 'clock_no_path']) {
      test(name, () {
        final text = _text(name);
        final log = jsonDecode(text) as Map<String, Object?>;
        expect(log['version'], '2.1.0');
        final run = (log['runs']! as List).single as Map<String, Object?>;
        final driver = (run['tool']! as Map)['driver']! as Map;
        expect(driver['name'], 'EDACrux Flow');
        for (final r
            in (run['results']! as List).cast<Map<String, Object?>>()) {
          for (final l in (r['locations'] as List? ?? const [])) {
            final art =
                ((l as Map)['physicalLocation'] as Map)['artifactLocation']
                    as Map;
            expect(art['uriBaseId'], 'SRCROOT');
            expect(art['uri'], _expected['design']);
          }
        }
      });
    }
  });

  group('LintCrux imports a flow timing path', () {
    for (final MapEntry(key: name, value: want) in cases.entries) {
      test(name, () async {
        final violations = await _import(_text(name));
        expect(violations, hasLength(1));
        final v = violations.single;

        // SARIF 3.27.5 ruleId, 3.27.10 level, 3.11 message text.
        expect(v.engineId, engineId);
        expect(v.ruleId, want['rule_id']);
        expect(v.severity, Severity.warning);
        expect(v.message, want['message']);
        expect(v.message, isNot(contains(RegExp('[0-9]+[.][0-9]'))));

        // SARIF 3.29 physicalLocation: file is the relative uri as written,
        // line and column are the RTL's own.
        expect(v.location.file, _expected['design']);
        final declared = _lineOf(
          _expected['end_register_declaration']! as String,
        );
        final line = want['anchor'] == 'declaration'
            ? declared
            : _rtl.indexWhere((l) => l.contains('$end <= ')) + 1;
        expect(v.location.line, line);
        final column = want['anchor'] == 'declaration'
            ? _rtl[line - 1].indexOf(end) + 1
            : _rtl[line - 1].indexOf(
                    _expected['end_statement_expression']! as String,
                  ) +
                  1;
        expect(v.location.column, column);

        // SARIF 3.27.22 relatedLocations: the path start, on its declaration.
        final start = want['start_register']! as String;
        expect(v.relatedLocations, hasLength(1));
        final related = v.relatedLocations.single;
        expect(related.file, _expected['design']);
        expect(related.line, _lineOf(want['start_declaration']! as String));
        expect(related.column, _rtl[related.line - 1].indexOf(start) + 1);

        // The file's own partialFingerprints (SARIF 3.27.17) survive in raw
        // only: LintCrux reads none of them.
        final fingerprints = v.raw['partialFingerprints']! as Map;
        expect(fingerprints[key], want['fingerprint']);
        expect(fingerprints, hasLength(1));
        expect(v.isAnalysisFailure, isFalse);
        expect(v.suppression, isNull);
      });
    }

    test('a run that meets timing imports as a run with no findings', () async {
      expect(await _import(_text('path_ice40_met')), isEmpty);
    });

    test('a failing clock the report names no path for', () async {
      final want = _expected['clock_no_path']! as Map<String, Object?>;
      final v = (await _import(_text('clock_no_path'))).single;
      expect(v.engineId, engineId);
      expect(v.ruleId, want['rule_id']);
      expect(v.severity, Severity.warning);
      expect(v.message, want['message']);
      // No locations in the SARIF: LintCrux's placeholder, line 1, no file.
      expect(v.location.file, isEmpty);
      expect(v.location.line, 1);
      expect((v.raw['partialFingerprints']! as Map)[key], want['fingerprint']);
    });

    test('the four families carry distinct fingerprints', () {
      final seen = {for (final c in cases.values) c['fingerprint']};
      expect(seen, hasLength(cases.length));
    });
  });

  group('re-imports and re-runs', () {
    test('loading the same file twice replaces, never duplicates', () async {
      final store = InMemoryViolationStore();
      final loader = SarifFileLoader();
      addTearDown(() async {
        loader.dispose();
        await store.dispose();
      });
      await loader.loadFromString(_text('path_ice40_violated'), store: store);
      await loader.loadFromString(_text('path_ice40_violated'), store: store);
      expect(store.all, hasLength(1));
      expect(store.byEngine[engineId], hasLength(1));
    });

    for (final name in cases.keys) {
      test(
        '$name: a rerun with different numbers matches its baseline',
        () async {
          final first = await _import(_text(name));
          final second = await _import(_rerun(_text(name)));
          // The rerun really differs where numbers live.
          expect(
            (second.single.raw['properties']! as Map)['achievedMhz'],
            isNot((first.single.raw['properties']! as Map)['achievedMhz']),
          );
          final baseline = LintBaseline(
            baselineId: 'b',
            createdAt: DateTime.utc(2000),
            projectPath: _root,
            frozenViolations: [
              for (final v in first)
                BaselineViolation.fromViolation(v, projectRoot: _root),
            ],
          );
          final delta = BaselineFilter.classify(
            current: second,
            baseline: baseline,
            projectRoot: _root,
          );
          expect(delta.newViolations, isEmpty);
          expect(delta.persistingViolations, hasLength(1));
          expect(delta.resolvedViolations, isEmpty);
        },
      );
    }

    test('another family is a different finding, not a match', () async {
      final ice40 = await _import(_text('path_ice40_violated'));
      final ecp5 = await _import(_text('path_ecp5_violated'));
      final baseline = LintBaseline(
        baselineId: 'b',
        createdAt: DateTime.utc(2000),
        projectPath: _root,
        frozenViolations: [
          for (final v in ice40)
            BaselineViolation.fromViolation(v, projectRoot: _root),
        ],
      );
      final delta = BaselineFilter.classify(
        current: ecp5,
        baseline: baseline,
        projectRoot: _root,
      );
      expect(delta.newViolations, hasLength(1));
      expect(delta.resolvedViolations, hasLength(1));
    });
  });

  test('findings, not signoff: no claim of signoff in any fixture', () {
    final claim = RegExp(
      'sign-?off|tape-?out|certif|qualif|guarantee|rtl to gds',
      caseSensitive: false,
    );
    final files = Directory(
      _dir,
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.sarif.json'));
    expect(files, hasLength(6));
    for (final f in files) {
      expect(f.readAsStringSync(), isNot(contains(claim)), reason: f.path);
    }
  });
}
