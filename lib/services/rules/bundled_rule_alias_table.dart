// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/interfaces/rule_alias_table.dart';
import 'package:lintcrux/services/rules/map_rule_alias_table.dart';

/// The rule aliases LintCrux ships (`lib/data/rule_aliases.json`), compiled
/// in: deprecated engine rule id → its current name.
///
/// The desktop app and the headless command-line binaries must match a
/// waiver against a renamed rule the same way, or a waiver that holds in the
/// app stops holding in CI. The binaries are plain Dart with no Flutter asset
/// bundle to read the JSON from, so both read this. The JSON stays the file a
/// contributor edits and the one the engine fixtures check against;
/// `test/static/bundled_rule_aliases_test.dart` fails when the two disagree
/// and says what to copy.
const Map<String, String> kBundledRuleAliases = <String, String>{
  'verilator/UNUSED': 'verilator/UNUSEDSIGNAL',
  'verilator/WIDTHCONCAT': 'verilator/WIDTH',
  'verible/legacy-no-tabs': 'verible/no-tabs',
};

/// A [RuleAliasTable] over [kBundledRuleAliases]: the table every LintCrux
/// waiver matcher uses, in the app and on the command line.
RuleAliasTable bundledRuleAliasTable() =>
    MapRuleAliasTable(kBundledRuleAliases);
