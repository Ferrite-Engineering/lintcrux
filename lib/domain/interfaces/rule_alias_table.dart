// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Maps deprecated engine rule ids to their current canonical names.
///
/// When an engine renames a rule across versions (Verilator's `UNUSED` →
/// `UNUSEDSIGNAL`), two things silently break:
///
/// 1. The parser may mis-attribute the diagnostic (caught by the
///    cross-version N/N-1 matrix).
/// 2. A waiver written against the old rule id silently stops matching —
///    the user's suppression evaporates with no warning.
///
/// The alias table closes (2): it is a community-maintained, data-driven
/// map of `old/rule` → `new/rule`. The waiver-match path resolves a
/// waiver's targeted rule id through the table, so a waiver written against
/// a renamed rule **still matches** the renamed violation, and surfaces a
/// localized "this waiver targets a renamed rule" diagnostic instead of
/// failing silently.
///
/// Declared in the open core, read only by the Pro overlay: waivers are a
/// Pro feature, and the overlay's waiver matcher is the one reader. The
/// default [ruleAliasTableProvider] binding is a no-op (empty) table; the
/// data-driven [MapRuleAliasTable] reads `lib/data/rule_aliases.json`.
abstract class RuleAliasTable {
  /// Resolves [ruleId] to its canonical name: if [ruleId] is a known
  /// deprecated alias, returns the current name; otherwise returns
  /// [ruleId] unchanged (unknown ids pass through).
  String resolve(String ruleId);

  /// Whether [ruleId] is a known deprecated alias (i.e. an engine renamed
  /// it and a current name exists). Unknown / current ids return false.
  bool isDeprecated(String ruleId);

  /// The canonical name for a deprecated [ruleId], or `null` when [ruleId]
  /// is not a known alias. (`canonicalFor(x) != null` ⇔ `isDeprecated(x)`.)
  String? canonicalFor(String ruleId);

  /// Every deprecated alias that now maps to [canonicalRuleId] — the
  /// reverse lookup, so a drift check can reconcile an N-1 rule id set
  /// against an N set. Empty when nothing aliases to [canonicalRuleId].
  Set<String> aliasesOf(String canonicalRuleId);
}
