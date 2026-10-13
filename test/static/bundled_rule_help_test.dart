// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/rules/bundled_rule_help.dart';
import 'package:lintcrux/services/rules/rule_database_provider.dart';

/// `bundledRuleHelpUri` is the headless binary's copy of the help-link
/// convention each rule database declares, so the two must agree for every
/// rule: the desktop app's "Learn more" and the SARIF descriptor's `helpUri`
/// must open the same page.
void main() {
  test('the compiled-in help URLs match every rule database entry', () {
    var checked = 0;
    for (final engineId in kShippedRuleDatabaseEngineIds) {
      final file = File('lib/data/rules/$engineId.json');
      expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
      final doc = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final base = doc['helpBaseUrl'];
      for (final raw in doc['rules'] as List) {
        final rule = raw as Map<String, dynamic>;
        final id = rule['id'] as String;
        final perRule = rule['helpUrl'];
        // The same derivation `RuleDatabase._parseEngineDoc` applies.
        final expected = perRule is String && perRule.isNotEmpty
            ? Uri.parse(perRule)
            : base is String && base.isNotEmpty
            ? Uri.parse('$base#$id')
            : null;
        if (expected == null) continue;
        checked++;
        expect(
          bundledRuleHelpUri(engineId, id),
          expected,
          reason: '$engineId/$id: bundledRuleHelpUri disagrees with the JSON',
        );
      }
    }
    expect(checked, greaterThan(100), reason: 'the sweep covered nothing');
  });

  test('an engine without a convention yields no link', () {
    expect(bundledRuleHelpUri('nonesuch', 'rule'), isNull);
    expect(bundledRuleHelpUri('verilator', ''), isNull);
  });
}
