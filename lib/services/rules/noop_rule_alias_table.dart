// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/interfaces/rule_alias_table.dart';

/// The empty [RuleAliasTable] — knows no aliases, so every id passes
/// through unchanged and nothing is ever deprecated.
///
/// This is the default open-core binding ([ruleAliasTableProvider]); the
/// data-driven [MapRuleAliasTable] is wired when the
/// `lib/data/rule_aliases.json` asset is loaded.
class NoopRuleAliasTable implements RuleAliasTable {
  /// Creates a [NoopRuleAliasTable].
  const NoopRuleAliasTable();

  @override
  String resolve(String ruleId) => ruleId;

  @override
  bool isDeprecated(String ruleId) => false;

  @override
  String? canonicalFor(String ruleId) => null;

  @override
  Set<String> aliasesOf(String canonicalRuleId) => const <String>{};
}
