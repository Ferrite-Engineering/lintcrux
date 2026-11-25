// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard: the headless binary's compiled-in rule catalogue
// (`lib/services/rules/bundled_rule_catalogue.dart`, which `lintcrux rule`
// reads) is exactly what the desktop app's `RuleDatabase` reads from
// `lib/data/rules/*.json`, rule by rule, through the app's own parser. A
// rule added to a database without regenerating the catalogue fails here:
//
//   dart run tool/generate_bundled_rule_catalogue.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/rules/bundled_rule_catalogue.dart';
import 'package:lintcrux/services/rules/rule_database.dart';
import 'package:path/path.dart' as p;

void main() {
  test('the catalogue is the rule databases, as the app reads them', () {
    final expected = <String, String>{};
    final files =
        Directory(p.join('lib', 'data', 'rules'))
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty);
    for (final file in files) {
      final engine = p.basenameWithoutExtension(file.path);
      final entry = RuleDatabase.parseEngineDocument(
        engine,
        file.readAsStringSync(),
      );
      expect(entry, isNotNull, reason: file.path);
      for (final rule in entry!.rules) {
        expected[rule.id] = rule.defaultSeverity.name;
      }
    }
    expect(kBundledRuleSeverities, expected);
    expect(kBundledRuleSeverities.length, greaterThan(500));
  });

  test('the summaries are the rule databases summaries, first-party only', () {
    final expected = <String, String>{};
    for (final file in Directory(p.join('lib', 'data', 'rules')).listSync()) {
      if (file is! File || !file.path.endsWith('.json')) continue;
      final engine = p.basenameWithoutExtension(file.path);
      final entry = RuleDatabase.parseEngineDocument(
        engine,
        file.readAsStringSync(),
      );
      for (final rule in entry!.rules) {
        if (rule.fullDescription.isNotEmpty) {
          expected[rule.id] = rule.fullDescription;
        }
      }
    }
    expect(kBundledRuleSummaries, expected);
    // Every `cdc` and `constraints` rule has one; no third-party rule does.
    for (final id in kBundledRuleSeverities.keys) {
      final firstParty = id.startsWith('cdc/') || id.startsWith('constraints/');
      expect(kBundledRuleSummaries.containsKey(id), firstParty, reason: id);
    }
    for (final summary in kBundledRuleSummaries.values) {
      expect(summary.endsWith('.'), isTrue, reason: summary);
      expect(summary, isNot(contains('—')), reason: summary);
    }
  });
}
