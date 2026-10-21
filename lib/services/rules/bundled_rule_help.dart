// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The help-URL conventions of the bundled rule databases
/// (`lib/data/rules/<engineId>.json`), compiled in.
///
/// The desktop app resolves a rule's help link through `RuleDatabase`,
/// which reads the JSON from the Flutter asset bundle. The headless binary
/// has no asset bundle, and a SARIF rule descriptor without a `helpUri` is
/// an alert page with no "learn more". Every engine's database derives its
/// links by one rule: a per-engine URL pattern over the rule id. That rule
/// is small enough to carry here, so both surfaces point at the same page
/// for the same rule. `test/static/bundled_rule_help_test.dart` holds this
/// table equal to what the JSON yields, rule by rule.
Uri? bundledRuleHelpUri(String engineId, String localRuleId) {
  if (localRuleId.isEmpty) return null;
  final id = Uri.encodeComponent(localRuleId);
  return switch (engineId) {
    'verilator' => Uri.parse('https://verilator.org/warn/$id'),
    'ghdl' => Uri.parse(
      'https://ghdl.github.io/ghdl/using/InvokingGHDL.html'
      '#cmdoption-ghdl-warn-$id',
    ),
    'slang' => Uri.parse('https://sv-lang.com/warning-ref.html#$id'),
    'svlint' => Uri.parse(
      'https://github.com/dalance/svlint/blob/master/MANUAL.md#$id',
    ),
    'verible' => Uri.parse(
      'https://chipsalliance.github.io/verible/lint.html#$id',
    ),
    'yosys' => Uri.parse(
      'https://yosyshq.readthedocs.io/projects/yosys/en/latest/cmd/check.html#$id',
    ),
    // First-party rules: the user documentation's rule table.
    'cdc' => Uri.parse('https://docs.lintcrux.app/cdc/#rules'),
    'constraints' => Uri.parse(
      'https://docs.lintcrux.app/pin-constraints/#$id',
    ),
    _ => null,
  };
}
