// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/interfaces/rule_alias_table.dart';
import 'package:lintcrux/services/rules/bundled_rule_alias_table.dart';
import 'package:lintcrux/services/rules/map_rule_alias_table.dart';
import 'package:lintcrux/services/rules/noop_rule_alias_table.dart';

/// Asset path of the community-maintained rule-alias map, as declared in
/// `pubspec.yaml`.
const String kRuleAliasAssetPath = 'lib/data/rule_aliases.json';

/// Candidate bundle keys for [kRuleAliasAssetPath], in priority order.
///
/// `packages/lintcrux/…` is the key Flutter assigns the asset when
/// `lintcrux` is consumed as a dependency (the `lintcrux_pro` overlay);
/// the bare key resolves when `lintcrux` is itself the root application.
/// [loadRuleAliasTable] tries both so it works from either app without
/// the caller knowing how it is packaged. (Without the prefixed key the
/// loader silently returned an empty table from the Pro app, leaving the
/// waiver rule-rename tolerance dead.)
const List<String> kRuleAliasAssetKeys = <String>[
  'packages/lintcrux/$kRuleAliasAssetPath',
  kRuleAliasAssetPath,
];

/// The app-wide [RuleAliasTable] consumed by the Pro overlay's waiver
/// matcher. Nothing in the open core reads it.
///
/// Default binding is the no-op (empty) table; the Pro app's startup reads
/// the committed `lib/data/rule_aliases.json` asset with [loadRuleAliasTable]
/// and overrides this provider with the loaded table.
final Provider<RuleAliasTable> ruleAliasTableProvider =
    Provider<RuleAliasTable>((ref) => const NoopRuleAliasTable());

/// Loads the data-driven [RuleAliasTable] from the first resolvable key in
/// [kRuleAliasAssetKeys].
///
/// Falls back to [bundledRuleAliasTable], the same aliases compiled in, when
/// no candidate key resolves, so a packaging without the asset matches
/// waivers exactly as the command-line binaries (which never have one) do.
/// Pass a test [bundle] to load a fixture.
Future<RuleAliasTable> loadRuleAliasTable({AssetBundle? bundle}) async {
  final assetBundle = bundle ?? rootBundle;
  for (final key in kRuleAliasAssetKeys) {
    try {
      final raw = await assetBundle.loadString(key);
      return MapRuleAliasTable.fromJsonString(raw);
    } on Object {
      // Key not bundled in this packaging context — try the next candidate.
    }
  }
  return bundledRuleAliasTable();
}
