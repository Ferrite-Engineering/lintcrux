// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard: every integration test that boots the app seeds EULA
// acceptance first.
//
// `CruxEulaGate` covers the app with a modal barrier until the agreement is
// accepted, so an integration test that boots unseeded has every tap miss.
// Integration tests run weekly, so the failure would surface up to a week
// late, behind whatever else broke that week. Widget tests have the same
// problem and the same cure, `test/support/eula_test_acceptance.dart`;
// `test/static/eula_gate_reachability_test.dart` is what keeps these seeds
// from quietly hiding an un-mounted gate.
//
// The scanner is `crux_eula`'s `cruxAuditEulaSeededBoots`, shared by the four
// products. A `bootstrap(` call counts as seeded when, earlier in the same
// function (or in a `setUp`), one of the seed helpers is called or
// `kCruxEulaAcceptedVersionKey` is named. LintCrux's integration tests boot
// through `bootLintcrux` in `integration_test/helpers/app_driver.dart`,
// which seeds through `seedFreshInstallPreferences` before it calls
// `bootstrap`; that helper is the one boot call this repository has, and a
// test that reaches for `bootstrap` directly is what this guard is for.

import 'dart:io';

import 'package:crux_eula/crux_eula_guards.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('every integration-test boot seeds EULA acceptance first', () {
    final root = Directory('integration_test');
    expect(root.existsSync(), isTrue, reason: 'run from the repository root');
    final sources = <CruxEulaGuardSource>[
      for (final entity in root.listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          CruxEulaGuardSource(
            path: p.relative(entity.path).replaceAll(r'\', '/'),
            source: entity.readAsStringSync(),
          ),
    ];
    expect(sources, isNotEmpty, reason: 'integration_test/ holds no Dart');

    // `bootstrap` is the scanner's default boot call and LintCrux's only one.
    final findings = cruxAuditEulaSeededBoots(
      sources: sources,
      seedCalls: const <String>{
        'seedFreshInstallPreferences',
        'seedEulaAcceptance',
      },
    );

    expect(
      findings,
      isEmpty,
      reason: findings.map((f) => f.toString()).join('\n'),
    );
  });
}
