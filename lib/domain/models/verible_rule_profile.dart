// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// The base set of rules Verible starts from, before a
/// [VeribleRuleProfile]'s own rule list is applied — upstream's
/// `--ruleset` flag.
enum VeribleBaseRuleset {
  /// `--ruleset=none` — start from an empty set. The profile's rule
  /// list is then the *complete* definition of what runs, which is what
  /// makes a named style-guide profile mean the same thing across
  /// Verible releases.
  none('none'),

  /// `--ruleset=default` — start from Verible's own default selection
  /// and treat the profile's list as a delta.
  defaults('default'),

  /// `--ruleset=all` — start from every registered rule.
  all('all');

  const VeribleBaseRuleset(this.flagValue);

  /// The literal value passed to `--ruleset=`.
  final String flagValue;
}

/// A named, curated selection of `verible-verilog-lint` rules.
///
/// This is **rule selection at engine-invocation time** — which checks
/// Verible runs — and is deliberately *not* the `FilterPreset` /
/// `NamedFilterPreset` mechanism, which filters the violation table
/// after a run has already produced results. A style-guide profile has
/// to change what the engine is asked to check, so it rides the
/// existing `LintProject.perEngineOptions['verible']` bag →
/// `LintRunRequest.options` → `VeribleEngine` command line, alongside
/// the `rulesConfigSearch` / `textModeFallback` options that already
/// live there.
///
/// [ruleSpecs] entries use Verible's own `--rules` token grammar:
///
/// * `no-tabs` — enable (a bare name, or an explicit `+` prefix)
/// * `-typedef-structs-unions` — disable
/// * `line-length=length:100` — enable with a configuration value
///
/// A spec must never contain a comma, because `--rules` is
/// comma-separated.
@immutable
class VeribleRuleProfile {
  /// Creates a [VeribleRuleProfile].
  const VeribleRuleProfile({
    required this.id,
    required this.ruleSpecs,
    required this.styleGuideUrl,
    required this.upstreamRevision,
    required this.verifiedAgainstVeribleVersion,
    this.baseRuleset = VeribleBaseRuleset.none,
  });

  /// Stable, machine-facing identifier. This is the value a project
  /// file carries in `perEngineOptions.verible.ruleProfile`, so it is
  /// part of the `project.lintcrux` contract and must not be renamed.
  final String id;

  /// The profile's rule tokens, in Verible `--rules` grammar.
  final List<String> ruleSpecs;

  /// What Verible starts from before [ruleSpecs] is applied.
  final VeribleBaseRuleset baseRuleset;

  /// Canonical URL of the human-readable style guide this profile
  /// encodes. Recorded so a reader can check the profile against its
  /// source without archaeology.
  final String styleGuideUrl;

  /// The upstream revision (commit SHA and date) of the document or
  /// machine-readable config this profile was transcribed from.
  /// Updating the profile starts by diffing against this revision.
  final String upstreamRevision;

  /// The `verible-verilog-lint` version(s) every entry in [ruleSpecs]
  /// was verified to exist in. Rules that do not exist make Verible
  /// exit non-zero having linted nothing, so this is a correctness
  /// claim, not a note.
  final String verifiedAgainstVeribleVersion;

  /// The bare rule names in [ruleSpecs], with any `+`/`-` prefix and
  /// any `=<config>` suffix stripped.
  List<String> get ruleIds => ruleSpecs.map(ruleIdOf).toList(growable: false);

  /// The rule names [ruleSpecs] turns *on*.
  List<String> get enabledRuleIds => <String>[
    for (final spec in ruleSpecs)
      if (!spec.startsWith('-')) ruleIdOf(spec),
  ];

  /// The command-line arguments this profile contributes to a
  /// `verible-verilog-lint` invocation.
  List<String> toVeribleArgs() => <String>[
    '--ruleset=${baseRuleset.flagValue}',
    '--rules=${ruleSpecs.join(',')}',
  ];

  /// Strips the `+`/`-` prefix and `=<config>` suffix from a single
  /// `--rules` token, yielding the bare Verible rule name.
  static String ruleIdOf(String spec) {
    final unprefixed = (spec.startsWith('+') || spec.startsWith('-'))
        ? spec.substring(1)
        : spec;
    final eq = unprefixed.indexOf('=');
    return eq < 0 ? unprefixed : unprefixed.substring(0, eq);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! VeribleRuleProfile) return false;
    if (other.id != id) return false;
    if (other.baseRuleset != baseRuleset) return false;
    if (other.styleGuideUrl != styleGuideUrl) return false;
    if (other.upstreamRevision != upstreamRevision) return false;
    if (other.verifiedAgainstVeribleVersion != verifiedAgainstVeribleVersion) {
      return false;
    }
    if (other.ruleSpecs.length != ruleSpecs.length) return false;
    for (var i = 0; i < ruleSpecs.length; i++) {
      if (other.ruleSpecs[i] != ruleSpecs[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    id,
    baseRuleset,
    styleGuideUrl,
    upstreamRevision,
    verifiedAgainstVeribleVersion,
    Object.hashAll(ruleSpecs),
  );

  @override
  String toString() =>
      'VeribleRuleProfile($id, ${ruleSpecs.length} rules, '
      'base ${baseRuleset.flagValue})';
}
