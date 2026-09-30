// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/interfaces/rule_alias_table.dart';
import 'package:lintcrux/services/engines/verilator/verilator_parser.dart';
import 'package:lintcrux/services/rules/map_rule_alias_table.dart';

/// Unit-level version-drift reconciliation, no live
/// binary required.
///
/// Feeds the parser two canned outputs — the current engine shape and the
/// N-1 shape from `test/fixtures/engines/verilator/generated/drift_*` —
/// and asserts the two normalized rule-id sets reconcile through the
/// committed rule-alias table: every N-1 rule id, once resolved, is present
/// in the current set. An *un*aliased difference fails loudly.
List<String> _ruleIdsFor(String caseName) {
  final file = File(
    'test/fixtures/engines/verilator/generated/$caseName/output.txt',
  );
  final lines = const LineSplitter().convert(file.readAsStringSync());
  return VerilatorParser(
    rootPath: '/work',
  ).parse(lines).map((v) => v.ruleId).toList();
}

void main() {
  final RuleAliasTable aliases = MapRuleAliasTable.fromJsonString(
    File('lib/data/rule_aliases.json').readAsStringSync(),
  );

  test(
    'current and N-1 verilator outputs reconcile through the alias table',
    () {
      final current = _ruleIdsFor('drift_current').toSet();
      final nMinus1 = _ruleIdsFor('drift_nminus1').toSet();

      // Sanity: the drift fixtures genuinely differ in raw rule id.
      expect(current, isNot(equals(nMinus1)));

      // Resolve every N-1 rule id through the alias table; the result must
      // be a subset of the current set — i.e. nothing is left unreconciled.
      final unreconciled = <String>[];
      for (final id in nMinus1) {
        final resolved = aliases.resolve(id);
        if (!current.contains(resolved)) {
          unreconciled.add('$id (resolved: $resolved)');
        }
      }

      expect(
        unreconciled,
        isEmpty,
        reason:
            'N-1 rule ids with no alias-table reconciliation to the '
            'current set:\n  ${unreconciled.join('\n  ')}',
      );
    },
  );

  test('the alias table actually carries the verilator UNUSED→UNUSEDSIGNAL '
      'reconciliation the drift fixtures depend on', () {
    // Guards the test above from passing vacuously if the fixtures or the
    // alias entry are removed.
    expect(_ruleIdsFor('drift_nminus1'), contains('verilator/UNUSED'));
    expect(_ruleIdsFor('drift_current'), contains('verilator/UNUSEDSIGNAL'));
    expect(aliases.resolve('verilator/UNUSED'), 'verilator/UNUSEDSIGNAL');
  });
}
