// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show CachingAssetBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/interfaces/rule_alias_table.dart';
import 'package:lintcrux/services/rules/map_rule_alias_table.dart';
import 'package:lintcrux/services/rules/noop_rule_alias_table.dart';
import 'package:lintcrux/services/rules/rule_alias_table_provider.dart';

/// Minimal [CachingAssetBundle] exposing a fixed key→string map so
/// [loadRuleAliasTable]'s candidate-key resolution can be exercised
/// without a real asset manifest.
class _FakeAssetBundle extends CachingAssetBundle {
  _FakeAssetBundle(this._assets);
  final Map<String, String> _assets;

  @override
  Future<ByteData> load(String key) async {
    final value = _assets[key];
    if (value == null) {
      throw Exception('Unable to load asset: "$key".');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(value)));
  }
}

/// Coverage for the rule-alias table: alias resolution, bidirectional lookup,
/// deprecated-waiver surfacing, and pass-through of unknown ids. Loads the
/// committed `lib/data/rule_aliases.json` so the test pins the shipped data.
RuleAliasTable _loadCommitted() {
  final raw = File('lib/data/rule_aliases.json').readAsStringSync();
  return MapRuleAliasTable.fromJsonString(raw);
}

void main() {
  group('MapRuleAliasTable (committed data)', () {
    final table = _loadCommitted();

    test('resolves a known deprecated alias to its canonical name', () {
      expect(table.resolve('verilator/UNUSED'), 'verilator/UNUSEDSIGNAL');
      expect(table.canonicalFor('verilator/UNUSED'), 'verilator/UNUSEDSIGNAL');
      expect(table.isDeprecated('verilator/UNUSED'), isTrue);
    });

    test('unknown / current ids pass through unchanged', () {
      expect(table.resolve('verilator/UNUSEDSIGNAL'), 'verilator/UNUSEDSIGNAL');
      expect(table.resolve('slang/Whatever'), 'slang/Whatever');
      expect(table.isDeprecated('verilator/UNUSEDSIGNAL'), isFalse);
      expect(table.canonicalFor('slang/Whatever'), isNull);
    });

    test('bidirectional lookup: aliasesOf returns every deprecated name', () {
      expect(
        table.aliasesOf('verilator/UNUSEDSIGNAL'),
        contains('verilator/UNUSED'),
      );
      expect(table.aliasesOf('verilator/UNUSEDSIGNAL'), isNotEmpty);
      expect(table.aliasesOf('nonexistent/rule'), isEmpty);
    });

    test('the documentation `_comment` key is not treated as an alias', () {
      expect(table.isDeprecated('_comment'), isFalse);
      expect(table.resolve('_comment'), '_comment');
    });
  });

  group('NoopRuleAliasTable', () {
    const table = NoopRuleAliasTable();
    test('knows no aliases — everything passes through', () {
      expect(table.resolve('verilator/UNUSED'), 'verilator/UNUSED');
      expect(table.isDeprecated('verilator/UNUSED'), isFalse);
      expect(table.canonicalFor('verilator/UNUSED'), isNull);
      expect(table.aliasesOf('verilator/UNUSEDSIGNAL'), isEmpty);
    });
  });

  group('loadRuleAliasTable candidate-key resolution', () {
    const json = '{"verilator/UNUSED": "verilator/UNUSEDSIGNAL"}';

    test('loads from the bare key (lintcrux as the root app)', () async {
      final table = await loadRuleAliasTable(
        bundle: _FakeAssetBundle(<String, String>{kRuleAliasAssetPath: json}),
      );
      expect(table.resolve('verilator/UNUSED'), 'verilator/UNUSEDSIGNAL');
    });

    test('loads from the packages/ key (lintcrux as a dependency, e.g. '
        'lintcrux_pro) when the bare key is absent', () async {
      // Only the prefixed key is present — mirrors what the Pro app sees.
      final table = await loadRuleAliasTable(
        bundle: _FakeAssetBundle(<String, String>{
          'packages/lintcrux/$kRuleAliasAssetPath': json,
        }),
      );
      expect(table.resolve('verilator/UNUSED'), 'verilator/UNUSEDSIGNAL');
    });

    test('falls back to the compiled-in aliases when no candidate key '
        'resolves', () async {
      // The same table the command-line binaries use, so a packaging without
      // the asset still matches a waiver on a renamed rule.
      final table = await loadRuleAliasTable(
        bundle: _FakeAssetBundle(const <String, String>{}),
      );
      expect(table.resolve('verilator/UNUSED'), 'verilator/UNUSEDSIGNAL');
      expect(table.isDeprecated('verilator/UNUSED'), isTrue);
    });
  });
}
