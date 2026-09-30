// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/models/verible_rule_profile.dart';

/// Key inside `LintProject.perEngineOptions['verible']` (and therefore
/// inside `LintRunRequest.options`) that names the
/// [VeribleRuleProfile] a run should use.
///
/// ```json
/// "perEngineOptions": {
///   "verible": { "ruleProfile": "lowrisc" }
/// }
/// ```
///
/// An unrecognized value is a hard error, not a silent fallback — see
/// `VeribleEngine`.
const String kVeribleRuleProfileOptionKey = 'ruleProfile';

/// Id of the lowRISC / OpenTitan Verilog style-guide profile.
const String kVeribleRuleProfileLowRisc = 'lowrisc';

/// `verible-verilog-lint` releases every rule name in the shipped
/// profiles was verified to exist in.
///
/// `v0.0-3795` is the release pinned for the bundled distribution in
/// `tool/bundled_engines.yaml`. `v0.0-4084` is a second, much later
/// release the same rule names were checked against — deliberately not
/// described as "the newest upstream", because that is a claim that goes
/// stale the week after it is written — upstream cuts releases
/// continuously and is well past `v0.0-4113`. What matters is the
/// span, not the ceiling: both releases expose the *same*
/// 42-rule default set (`--generate_markdown` reports 42 of 61
/// registered rules "Enabled by default: true" on 4084), so the profile
/// below is valid on everything in between.
///
/// Verification method (repeatable):
///
/// ```sh
/// verible-verilog-lint --generate_markdown          # rule catalog
/// verible-verilog-lint --ruleset=none --rules=<...> some.sv
/// ```
///
/// A `--rules` spec naming a rule the binary does not have makes
/// Verible exit non-zero having linted nothing, which `VeribleEngine`
/// correctly reports as a failed run — so an unverified rule name is a
/// broken profile, not a cosmetic defect.
const String kVeribleRuleProfileVerifiedVersions =
    'v0.0-3795-gf4d72375, v0.0-4084-gf3e4d98b';

/// The lowRISC / OpenTitan Verilog style guide, expressed as a Verible
/// rule selection.
///
/// **Upstream sources this encodes**
///
/// * Prose style guide — `lowRISC/style-guides`,
///   `VerilogCodingStyle.md`, revision
///   `9c15ff5dce23eef969e00ab3715153967419eadd`.
/// * Machine-readable enforcement — `lowRISC/opentitan`,
///   `hw/lint/tools/veriblelint/lowrisc-styleguide.rules.verible_lint`,
///   revision `30d7e787c753caaa03fe68a4a70da1bbcbc1d96f`.
///   That file is a *delta* on Verible's default rule set:
///
///   ```text
///   line-length=length:100
///   explicit-parameter-storage-type=exempt_type:string
///   parameter-name-style=localparam_style:CamelCase|ALL_CAPS
///   -typedef-structs-unions
///   ```
///
/// To refresh this profile, diff those two revisions against the ones
/// cited here — no archaeology required.
///
/// **Why the rules are listed explicitly rather than as a delta.**
/// Upstream leans on `--ruleset=default`, so what "the lowRISC profile"
/// checks silently changes whenever Verible promotes or demotes a rule
/// in its default set. A profile that ships under a style guide's name
/// must be reproducible, so LintCrux resolves the delta *once*, at the
/// verified Verible versions, and ships the resulting closed set with
/// `--ruleset=none`. The set below is exactly Verible's 42 default
/// rules minus `typedef-structs-unions` (lowRISC permits nested struct
/// definitions), carrying upstream's three configuration values.
///
/// A project's own `.rules.verible_lint` still applies on top when
/// `rulesConfigSearch` is on — the profile is a starting point, not a
/// lock.
final VeribleRuleProfile lowRiscVeribleRuleProfile = VeribleRuleProfile(
  id: kVeribleRuleProfileLowRisc,
  styleGuideUrl:
      'https://github.com/lowRISC/style-guides/blob/master/VerilogCodingStyle.md',
  upstreamRevision:
      'lowRISC/style-guides@9c15ff5dce23eef969e00ab3715153967419eadd; '
      'lowRISC/opentitan@30d7e787c753caaa03fe68a4a70da1bbcbc1d96f',
  verifiedAgainstVeribleVersion: kVeribleRuleProfileVerifiedVersions,
  ruleSpecs: List<String>.unmodifiable(<String>[
    'always-comb',
    'always-comb-blocking',
    'always-ff-non-blocking',
    'case-missing-default',
    'constraint-name-style',
    'create-object-name-match',
    'enum-name-style',
    'explicit-function-lifetime',
    'explicit-function-task-parameter-type',
    // OpenTitan allows "classic" Verilog string parameters with no
    // explicit storage type.
    'explicit-parameter-storage-type=exempt_type:string',
    'explicit-task-lifetime',
    'forbid-consecutive-null-statements',
    'forbid-defparam',
    'forbid-line-continuations',
    'forbidden-macro',
    'generate-label',
    'generate-label-prefix',
    'interface-name-style',
    'invalid-system-task-function',
    'line-length=length:100',
    'macro-name-style',
    'module-begin-block',
    'module-filename',
    'module-parameter',
    'module-port',
    'no-tabs',
    'no-trailing-spaces',
    'package-filename',
    'packed-dimensions-range-ordering',
    // localparams may be CamelCase or ALL_CAPS under the lowRISC guide.
    'parameter-name-style=localparam_style:CamelCase|ALL_CAPS',
    'plusarg-assignment',
    'positive-meaning-parameter-name',
    'posix-eof',
    'struct-union-name-style',
    'suggest-parentheses',
    'truncated-numeric-literal',
    'typedef-enums',
    // `typedef-structs-unions` is deliberately absent: lowRISC permits
    // nested struct definitions (`-typedef-structs-unions` upstream).
    'undersized-binary-literal',
    'unpacked-dimensions-range-ordering',
    'v2001-generate-begin',
    'void-cast',
  ]),
);

/// Every rule profile shipped by open core.
///
/// Curated convenience, not a paid feature — the profiles ship on every
/// tier, the same way `builtinFilterPresets()` does.
///
/// Each call returns a fresh list so a caller that intends to mutate
/// (e.g. a test prepending a synthetic profile) cannot corrupt the
/// shared one.
List<VeribleRuleProfile> builtinVeribleRuleProfiles() => <VeribleRuleProfile>[
  lowRiscVeribleRuleProfile,
];

/// Looks up a built-in profile by [id], or `null` when no profile
/// carries that id. Callers must treat `null` as an error rather than
/// as "run with defaults" — silently ignoring a mistyped profile id
/// would make a project lint against a rule set nobody chose.
VeribleRuleProfile? veribleRuleProfileById(String id) {
  for (final profile in builtinVeribleRuleProfiles()) {
    if (profile.id == id) return profile;
  }
  return null;
}
