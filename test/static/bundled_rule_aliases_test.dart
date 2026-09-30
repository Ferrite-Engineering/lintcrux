// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/rules/bundled_rule_alias_table.dart';

/// Static guard: the compiled-in rule aliases are exactly
/// `lib/data/rule_aliases.json`.
///
/// The JSON is the file contributors edit; the constant is what the app and
/// the command-line binaries match waivers with. If they drift, a waiver on
/// a renamed rule holds on one surface and not the other.
///
/// MUTATION: add, drop or change an entry in either and this fails, naming
/// the difference.
void main() {
  test('kBundledRuleAliases matches lib/data/rule_aliases.json', () {
    final decoded =
        jsonDecode(File('lib/data/rule_aliases.json').readAsStringSync())
            as Map<String, Object?>;
    final fromJson = <String, String>{
      for (final entry in decoded.entries)
        if (!entry.key.startsWith('_') && entry.value is String)
          entry.key: entry.value! as String,
    };
    expect(
      kBundledRuleAliases,
      fromJson,
      reason:
          'lib/services/rules/bundled_rule_alias_table.dart no longer matches '
          'lib/data/rule_aliases.json. Copy the JSON entries (without the '
          'underscore-prefixed comment keys) into kBundledRuleAliases.',
    );
  });

  test('the bundled table resolves a deprecated id to its current name', () {
    final table = bundledRuleAliasTable();
    for (final entry in kBundledRuleAliases.entries) {
      expect(table.canonicalFor(entry.key), entry.value);
    }
  });
}
