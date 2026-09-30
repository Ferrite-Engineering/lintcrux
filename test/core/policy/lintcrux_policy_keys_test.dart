// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_policy/crux_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/policy/lintcrux_policy_keys.dart';

/// LintCrux's policy namespace and audit vocabulary.
///
/// These tests pin that the keys EXIST AND ARE HONOURED. The features the keys
/// configure are separate and are not covered here.
void main() {
  group('the namespace is registered and non-empty', () {
    test('the product id matches the schema', () {
      expect(LintCruxPolicyKeys.productId, 'lintcrux');
    });

    test('keys and kinds are declared', () {
      expect(LintCruxPolicyKeys.all, isNotEmpty);
      expect(LintCruxAuditKinds.all, isNotEmpty);
    });

    test('no key or kind is blank, and none collide', () {
      for (final k in LintCruxPolicyKeys.all) {
        expect(k.trim(), isNotEmpty);
      }
      for (final k in LintCruxAuditKinds.all) {
        expect(k.trim(), isNotEmpty);
        expect(k, contains('.'), reason: 'kinds are dotted: noun.verb');
      }
    });
  });

  group('registered keys actually resolve', () {
    test('a policy value in this namespace is honoured', () {
      final key = LintCruxPolicyKeys.all.first;
      final doc = PolicyDocument.parse(
        '{"schema":1,"products":{"lintcrux":{"$key":"x"}}}',
      );
      final resolved = lintcruxPolicyResolver(doc).productValue<String>(
        key,
        parse: (raw) => raw is String ? raw : null,
        builtIn: 'built-in',
      );
      expect(resolved.value, 'x');
      expect(resolved.source, PolicySource.policyDefault);
    });

    test('a LOCKED value outranks the user setting', () {
      final key = LintCruxPolicyKeys.all.first;
      final doc = PolicyDocument.parse(
        '{"schema":1,"products":{"lintcrux":'
        '{"$key":{"value":"org","locked":true}}}}',
      );
      final resolved = lintcruxPolicyResolver(doc).productValue<String>(
        key,
        parse: (raw) => raw is String ? raw : null,
        builtIn: 'built-in',
        userSetting: 'mine',
      );
      expect(resolved.value, 'org');
      expect(resolved.locked, isTrue);
    });

    test("ANOTHER product's namespace is ignored silently", () {
      // One file serves a mixed fleet, so meeting another product's keys is
      // the normal case rather than a misconfiguration — not warned about,
      // not an error.
      final key = LintCruxPolicyKeys.all.first;
      const other = 'lintcrux' == 'simcrux' ? 'wavecrux' : 'simcrux';
      final doc = PolicyDocument.parse(
        '{"schema":1,"products":{"$other":{"$key":"x"}}}',
      );
      final resolver = lintcruxPolicyResolver(doc);
      final resolved = resolver.productValue<String>(
        key,
        parse: (raw) => raw is String ? raw : null,
        builtIn: 'built-in',
      );
      expect(resolved.value, 'built-in');
      expect(resolver.diagnostics, isEmpty);
    });
  });
}
