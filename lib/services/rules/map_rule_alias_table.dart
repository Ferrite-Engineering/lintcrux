// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:lintcrux/domain/interfaces/rule_alias_table.dart';

/// Data-driven [RuleAliasTable] backed by an `alias → canonical` map.
///
/// The map is the deserialized form of `lib/data/rule_aliases.json`:
///
/// ```json
/// { "verilator/UNUSED": "verilator/UNUSEDSIGNAL",
///   "verible/legacy-name": "verible/new-name" }
/// ```
///
/// Each key is a *deprecated* rule id and each value its current canonical
/// name. The reverse index ([aliasesOf]) is precomputed once at
/// construction so drift reconciliation is O(1) per lookup.
class MapRuleAliasTable implements RuleAliasTable {
  /// Creates a table from an `alias → canonical` [aliases] map.
  MapRuleAliasTable(Map<String, String> aliases)
    : _aliases = Map<String, String>.unmodifiable(aliases),
      _reverse = _buildReverse(aliases);

  /// Parses a `rule_aliases.json` document (a flat JSON object of
  /// `"alias": "canonical"` string pairs) into a table. Non-string values
  /// are ignored so a malformed entry never crashes the load.
  factory MapRuleAliasTable.fromJsonString(String jsonString) {
    final decoded = jsonDecode(jsonString);
    final out = <String, String>{};
    if (decoded is Map<String, dynamic>) {
      for (final entry in decoded.entries) {
        // Underscore-prefixed keys are documentation (e.g. `_comment`),
        // not aliases.
        if (entry.key.startsWith('_')) continue;
        final value = entry.value;
        if (value is String && value.isNotEmpty) {
          out[entry.key] = value;
        }
      }
    }
    return MapRuleAliasTable(out);
  }

  final Map<String, String> _aliases;
  final Map<String, Set<String>> _reverse;

  static Map<String, Set<String>> _buildReverse(Map<String, String> aliases) {
    final reverse = <String, Set<String>>{};
    aliases.forEach((alias, canonical) {
      (reverse[canonical] ??= <String>{}).add(alias);
    });
    return reverse.map(
      (k, v) => MapEntry(k, Set<String>.unmodifiable(v)),
    );
  }

  @override
  String resolve(String ruleId) => _aliases[ruleId] ?? ruleId;

  @override
  bool isDeprecated(String ruleId) => _aliases.containsKey(ruleId);

  @override
  String? canonicalFor(String ruleId) => _aliases[ruleId];

  @override
  Set<String> aliasesOf(String canonicalRuleId) =>
      _reverse[canonicalRuleId] ?? const <String>{};
}
