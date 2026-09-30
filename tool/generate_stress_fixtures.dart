// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Generator for the large-scale stress corpus's committed artifacts.
//
// The 50K / 100K corpora themselves are NOT committed as multi-MB binaries:
// they are regenerated deterministically in memory from a seed by
// `test/support/stress_corpus.dart` (byte-stable, reproducible, and free of
// the git-size / gzip-nondeterminism cost of committing them). This tool
// writes only the small committed artifacts that pin that generation and
// the malformed-input rejection cases, into both the `test/` tree and the
// `verification/` mirror in one pass so they cannot drift:
//
//   violations_50k.expected.meta.json   distribution counts of the 50K set
//   sarif_malformed/truncated.sarif.json
//   sarif_malformed/bad_token.sarif.json
//   sarif_malformed/wrong_schema.sarif.json
//
// Run from the lintcrux package root:
//
//   dart run tool/generate_stress_fixtures.dart
import 'dart:convert';
import 'dart:io';

import '../test/support/stress_corpus.dart';

/// Malformed SARIF documents that must be rejected with a typed
/// `SarifReadException` without corrupting any prior store contents.
const Map<String, String> _malformed = <String, String>{
  // Cut off mid-results-array — the stream ends inside a value.
  'truncated':
      '{"version":"2.1.0","runs":[{"tool":{"driver":'
      '{"name":"verilator"}},"results":[{"ruleId":"UNUSED","level":'
      '"warning","message":{"text":"truncated here',
  // Structurally broken token where a value is expected.
  'bad_token':
      '{"version":"2.1.0","runs":[{"tool":{"driver":'
      '{"name":"verilator"}},"results":[ %%%bad%%% ]}]}',
  // Valid JSON, but not a SARIF document (no runs array).
  'wrong_schema': '{"hello":"world","not":"sarif"}',
};

void main() {
  const encoder = JsonEncoder.withIndent('  ');
  final roots = <String>[
    'test/fixtures/stress',
    'verification/fixtures/stress',
  ];

  final meta = stressMeta(50000);
  final metaJson = '${encoder.convert(meta)}\n';

  for (final root in roots) {
    Directory(root).createSync(recursive: true);
    File('$root/violations_50k.expected.meta.json').writeAsStringSync(metaJson);
    final malformedDir = Directory('$root/sarif_malformed')
      ..createSync(recursive: true);
    _malformed.forEach((name, body) {
      File('${malformedDir.path}/$name.sarif.json').writeAsStringSync(body);
    });
  }

  stdout.writeln(
    'generate_stress_fixtures: wrote meta (${meta['total']} violations, '
    '${meta['distinctFiles']} files) + ${_malformed.length} malformed cases '
    '× ${roots.length} trees.',
  );
}
