// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/verible_rule_profile.dart';
import 'package:lintcrux/services/engines/verible/builtin_rule_profiles.dart';
import 'package:lintcrux/services/rules/rule_database.dart';

/// A `--rules` token: an optional `+`/`-`, a kebab-case rule name, and
/// an optional `=<config>` tail. Commas are forbidden anywhere —
/// `--rules` is comma-separated, so a comma inside a spec would silently
/// split one rule into two nonexistent ones.
final RegExp _specPattern = RegExp(r'^[+-]?[a-z0-9]+(-[a-z0-9]+)*(=[^,]+)?$');

void main() {
  group('builtinVeribleRuleProfiles', () {
    test('ships the lowRISC / OpenTitan profile', () {
      final ids = builtinVeribleRuleProfiles().map((p) => p.id).toList();
      expect(ids, contains(kVeribleRuleProfileLowRisc));
    });

    test('every profile id is unique', () {
      final ids = builtinVeribleRuleProfiles().map((p) => p.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('returns a fresh list per call so callers cannot corrupt it', () {
      final first = builtinVeribleRuleProfiles()..clear();
      expect(first, isEmpty);
      expect(builtinVeribleRuleProfiles(), isNotEmpty);
    });

    test('every shipped profile selects a non-empty, well-formed rule set', () {
      for (final profile in builtinVeribleRuleProfiles()) {
        expect(profile.ruleSpecs, isNotEmpty, reason: profile.id);
        expect(
          profile.ruleIds.toSet(),
          hasLength(profile.ruleIds.length),
          reason: '${profile.id} names a rule twice',
        );
        for (final spec in profile.ruleSpecs) {
          expect(
            _specPattern.hasMatch(spec),
            isTrue,
            reason: '${profile.id}: malformed --rules token "$spec"',
          );
        }
        expect(profile.upstreamRevision, isNotEmpty, reason: profile.id);
        expect(
          profile.styleGuideUrl,
          startsWith('https://'),
          reason: profile.id,
        );
        expect(
          profile.verifiedAgainstVeribleVersion,
          isNotEmpty,
          reason: profile.id,
        );
      }
    });
  });

  group('veribleRuleProfileById', () {
    test('resolves a shipped id', () {
      final profile = veribleRuleProfileById(kVeribleRuleProfileLowRisc);
      expect(profile, isNotNull);
      expect(profile!.id, kVeribleRuleProfileLowRisc);
    });

    test('returns null for an unknown id', () {
      expect(veribleRuleProfileById('not-a-profile'), isNull);
      expect(veribleRuleProfileById(''), isNull);
    });
  });

  group('lowRiscVeribleRuleProfile', () {
    test('selects a substantial, fully-enabled rule set', () {
      final profile = lowRiscVeribleRuleProfile;
      expect(profile.ruleSpecs.length, greaterThanOrEqualTo(40));
      // Verible's 42 default rules minus typedef-structs-unions; the
      // profile is a closed set, so nothing is expressed as a disable.
      expect(profile.enabledRuleIds, hasLength(profile.ruleSpecs.length));
      expect(profile.baseRuleset, VeribleBaseRuleset.none);
    });

    test('omits typedef-structs-unions — lowRISC allows nested structs', () {
      expect(
        lowRiscVeribleRuleProfile.ruleIds,
        isNot(contains('typedef-structs-unions')),
      );
    });

    test('carries the three upstream configuration values verbatim', () {
      expect(
        lowRiscVeribleRuleProfile.ruleSpecs,
        containsAll(<String>[
          'line-length=length:100',
          'explicit-parameter-storage-type=exempt_type:string',
          'parameter-name-style=localparam_style:CamelCase|ALL_CAPS',
        ]),
      );
    });

    test('cites the upstream revisions it encodes', () {
      final profile = lowRiscVeribleRuleProfile;
      expect(profile.upstreamRevision, contains('lowRISC/style-guides@'));
      expect(profile.upstreamRevision, contains('lowRISC/opentitan@'));
      expect(profile.styleGuideUrl, contains('VerilogCodingStyle.md'));
    });

    test('produces a single --rules argument Verible can parse', () {
      final args = lowRiscVeribleRuleProfile.toVeribleArgs();
      expect(args, hasLength(2));
      expect(args.first, '--ruleset=none');
      expect(args.last, startsWith('--rules='));
      final joined = args.last.substring('--rules='.length);
      expect(
        joined.split(','),
        hasLength(lowRiscVeribleRuleProfile.ruleSpecs.length),
      );
    });

    test(
      'every selected rule exists in the bundled Verible rule database',
      () async {
        // The rule database is itself verified against the
        // `verible-verilog-lint` releases named in its
        // `verifiedAgainstVeribleVersions` field, so this is the in-repo
        // oracle for "this rule name is real". A profile naming a rule
        // Verible does not have makes the binary exit non-zero having
        // linted nothing.
        TestWidgetsFlutterBinding.ensureInitialized();
        final db = await RuleDatabase.load(engineIds: <String>['verible']);
        expect(db.rulesFor('verible'), isNotEmpty);
        for (final ruleId in lowRiscVeribleRuleProfile.ruleIds) {
          expect(
            db.lookupBy(engineId: 'verible', localRuleId: ruleId),
            isNotNull,
            reason: 'lowRISC profile names unknown Verible rule "$ruleId"',
          );
        }
      },
    );
  });
}
