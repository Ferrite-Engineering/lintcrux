// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/verible_rule_profile.dart';

VeribleRuleProfile _profile({
  String id = 'demo',
  List<String> ruleSpecs = const <String>['no-tabs'],
  VeribleBaseRuleset baseRuleset = VeribleBaseRuleset.none,
}) {
  return VeribleRuleProfile(
    id: id,
    ruleSpecs: ruleSpecs,
    baseRuleset: baseRuleset,
    styleGuideUrl: 'https://example.test/guide',
    upstreamRevision: 'deadbeef',
    verifiedAgainstVeribleVersion: 'v0.0-0000-gtest',
  );
}

void main() {
  group('VeribleRuleProfile.ruleIdOf', () {
    test('returns a bare name unchanged', () {
      expect(VeribleRuleProfile.ruleIdOf('no-tabs'), 'no-tabs');
    });

    test('strips a leading + or -', () {
      expect(VeribleRuleProfile.ruleIdOf('+no-tabs'), 'no-tabs');
      expect(
        VeribleRuleProfile.ruleIdOf('-typedef-structs-unions'),
        'typedef-structs-unions',
      );
    });

    test('strips a =<config> suffix', () {
      expect(
        VeribleRuleProfile.ruleIdOf('line-length=length:100'),
        'line-length',
      );
    });

    test('strips both prefix and config suffix', () {
      expect(
        VeribleRuleProfile.ruleIdOf('+parameter-name-style=localparam_style:X'),
        'parameter-name-style',
      );
    });
  });

  group('VeribleRuleProfile', () {
    test('ruleIds reports every spec, enabledRuleIds skips disables', () {
      final profile = _profile(
        ruleSpecs: const <String>[
          'no-tabs',
          'line-length=length:100',
          '-typedef-structs-unions',
        ],
      );
      expect(profile.ruleIds, <String>[
        'no-tabs',
        'line-length',
        'typedef-structs-unions',
      ]);
      expect(profile.enabledRuleIds, <String>['no-tabs', 'line-length']);
    });

    test('toVeribleArgs emits --ruleset and a comma-joined --rules', () {
      final profile = _profile(
        ruleSpecs: const <String>['no-tabs', 'line-length=length:100'],
      );
      expect(profile.toVeribleArgs(), <String>[
        '--ruleset=none',
        '--rules=no-tabs,line-length=length:100',
      ]);
    });

    test('toVeribleArgs honors a non-default base ruleset', () {
      final profile = _profile(
        ruleSpecs: const <String>['-no-tabs'],
        baseRuleset: VeribleBaseRuleset.defaults,
      );
      expect(profile.toVeribleArgs().first, '--ruleset=default');
    });

    test('equality is by value, including rule order', () {
      expect(_profile(), _profile());
      expect(_profile().hashCode, _profile().hashCode);
      expect(
        _profile(ruleSpecs: const <String>['a', 'b']),
        isNot(_profile(ruleSpecs: const <String>['b', 'a'])),
      );
      expect(_profile(id: 'a'), isNot(_profile(id: 'b')));
      expect(
        _profile(baseRuleset: VeribleBaseRuleset.all),
        isNot(_profile()),
      );
    });

    test('toString names the id and rule count', () {
      final s = _profile(ruleSpecs: const <String>['a', 'b']).toString();
      expect(s, contains('demo'));
      expect(s, contains('2 rules'));
    });

    test('every base ruleset maps to an upstream --ruleset value', () {
      expect(
        VeribleBaseRuleset.values.map((v) => v.flagValue).toList(),
        <String>['none', 'default', 'all'],
      );
    });
  });
}
