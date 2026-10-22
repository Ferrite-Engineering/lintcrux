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

const _dir = 'verification/fixtures/sarif/flow/librelane';
const _root = '/work/design';

/// SARIF produced by the suite's flow writer from captured LibreLane runs
/// (see `verification/fixtures/sarif/flow/librelane/PROVENANCE.md`). The
/// physical checks (design rules, LVS, antenna) have no source location: they
/// are findings about the layout. Every expectation is in `expected.json`,
/// written by hand from the metrics and error records of the LibreLane runs
/// and the SARIF 2.1.0 meaning of the files, never from what LintCrux's
/// importer returns.
final Map<String, Object?> _expected =
    jsonDecode(File('$_dir/expected.json').readAsStringSync())
        as Map<String, Object?>;

String _text(String name) => File('$_dir/$name.sarif.json').readAsStringSync();

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

/// [json] with every count the report carries moved: the same design run
/// again with different numbers of violations.
String _rerun(String json) => json.replaceAllMapped(
  RegExp('("value": )([0-9]+)'),
  (m) => '${m[1]}${int.parse(m[2]!) + 7}',
);

Severity _severity(String name) => switch (name) {
  'warning' => Severity.warning,
  'note' => Severity.note,
  _ => throw ArgumentError(name),
};

void main() {
  final cases = (_expected['cases']! as Map<String, Object?>)
      .cast<String, Map<String, Object?>>();
  final engineId = _expected['engine_id']! as String;
  final key = _expected['fingerprint_key']! as String;

  group('the fixtures are SARIF 2.1.0 with no location on any result', () {
    for (final name in cases.keys) {
      test(name, () {
        final log = jsonDecode(_text(name)) as Map<String, Object?>;
        expect(log['version'], '2.1.0');
        final run = (log['runs']! as List).single as Map<String, Object?>;
        final driver = (run['tool']! as Map)['driver']! as Map;
        expect(driver['name'], 'EDACrux Flow');
        final results = (run['results']! as List).cast<Map<String, Object?>>();
        expect(results, hasLength((cases[name]!['results']! as List).length));
        for (final r in results) {
          expect(r.containsKey('locations'), isFalse);
          expect(r.containsKey('relatedLocations'), isFalse);
        }
      });
    }
  });

  group('LintCrux imports a physical finding', () {
    for (final MapEntry(key: name, value: want) in cases.entries) {
      test(name, () async {
        final wanted = (want['results']! as List).cast<Map<String, Object?>>();
        final violations = await _import(_text(name));
        expect(violations, hasLength(wanted.length));
        for (var i = 0; i < wanted.length; i++) {
          final v = violations[i];
          final w = wanted[i];
          // SARIF 3.27.5 ruleId, 3.27.10 level, 3.11 message text. The tool
          // is the engine id; the rule id keeps its own `flow/` namespace.
          expect(v.engineId, engineId);
          expect(v.ruleId, w['rule_id']);
          expect(v.severity, _severity(w['severity']! as String));
          expect(v.message, w['message']);
          // Not dropped, and not placed on a line of any file: the result
          // has no location, so LintCrux's placeholder has no file at all.
          expect(v.location.file, isEmpty);
          expect(v.relatedLocations, isEmpty);
          // The counts and whether LibreLane enforces the check are in
          // properties, which survive in raw with the fingerprint.
          final props = v.raw['properties']! as Map;
          expect(props['metric'], w['metric']);
          expect(props['value'], w['value']);
          expect(props['enforcedByLibreLane'], w['enforced']);
          expect(v.message, isNot(contains(RegExp('[0-9]'))));
          final fingerprints = v.raw['partialFingerprints']! as Map;
          expect(fingerprints, hasLength(1));
          expect(fingerprints[key], isNotEmpty);
          expect(v.isAnalysisFailure, isFalse);
          expect(v.suppression, isNull);
        }
      });
    }

    test('a check LibreLane is told only to warn about stays a note', () async {
      // sky130A_drc runs with ERROR_ON_TR_DRC false (its resolved.json), so
      // the routing DRC count is a note while the enforced Magic and KLayout
      // counts are warnings.
      final v = await _import(_text('sky130A_drc'));
      final byMetric = {
        for (final r in v)
          (r.raw['properties']! as Map)['metric']! as String: r.severity,
      };
      expect(byMetric['route__drc_errors'], Severity.note);
      expect(byMetric['magic__drc_error__count'], Severity.warning);
      expect(byMetric['klayout__drc_error__count'], Severity.warning);
    });

    test('a run that meets every check imports with no findings', () async {
      expect(await _import(_text('sky130A_met')), isEmpty);
    });

    test('a check that did not run is absent, never a zero finding', () async {
      // gf180mcuD skips KLayout DRC (KLAYOUT_DRC_RUNSET is null in its
      // resolved.json): its metrics carry no klayout__drc_error__count.
      final metric = _expected['klayout_metric_absent_on_gf180mcuD']! as String;
      expect(_text('gf180mcuD_met'), isNot(contains(metric)));
      final v = await _import(_text('gf180mcuD_met'));
      expect(v.where((r) => r.ruleId == 'flow/drc'), isEmpty);
    });

    test('the same rule and file with another metric is another finding', () {
      return _import(_text('sky130A_drc')).then((v) {
        expect({for (final r in v) r.message}, hasLength(v.length));
      });
    });
  });

  group('re-runs', () {
    for (final name in cases.keys.where((n) => n != 'sky130A_met')) {
      test(
        '$name: a rerun with different counts matches its baseline',
        () async {
          final first = await _import(_text(name));
          final second = await _import(_rerun(_text(name)));
          final firstProps = [
            for (final v in first) v.raw['properties']! as Map,
          ];
          final secondProps = [
            for (final v in second) v.raw['properties']! as Map,
          ];
          for (var i = 0; i < first.length; i++) {
            expect(secondProps[i]['value'], isNot(firstProps[i]['value']));
          }
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
          expect(delta.persistingViolations, hasLength(first.length));
          expect(delta.resolvedViolations, isEmpty);
        },
      );
    }

    test('a finding that is gone resolves, one that appears is new', () async {
      final drc = await _import(_text('sky130A_drc'));
      final antenna = await _import(_text('sky130A_antenna'));
      final baseline = LintBaseline(
        baselineId: 'b',
        createdAt: DateTime.utc(2000),
        projectPath: _root,
        frozenViolations: [
          for (final v in drc)
            BaselineViolation.fromViolation(v, projectRoot: _root),
        ],
      );
      final delta = BaselineFilter.classify(
        current: antenna,
        baseline: baseline,
        projectRoot: _root,
      );
      expect(delta.newViolations, hasLength(antenna.length));
      expect(delta.resolvedViolations, hasLength(drc.length));
      expect(delta.persistingViolations, isEmpty);
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
    expect(files, hasLength(cases.length));
    for (final f in files) {
      expect(f.readAsStringSync(), isNot(contains(claim)), reason: f.path);
    }
  });
}
