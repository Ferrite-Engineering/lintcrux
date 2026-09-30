// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/services/rules/rule_database.dart';

/// In-memory [AssetBundle] for testing the loader without going through
/// the Flutter asset pipeline.
class _MapBundle extends CachingAssetBundle {
  _MapBundle(this.assets);
  final Map<String, String> assets;

  @override
  Future<ByteData> load(String key) async {
    final value = assets[key];
    if (value == null) {
      throw FlutterError('Unable to load asset: "$key"');
    }
    final bytes = Uint8List.fromList(value.codeUnits);
    return ByteData.view(bytes.buffer);
  }
}

const _verilatorJson = '''
{
  "engineId": "verilator",
  "displayName": "Verilator",
  "helpBaseUrl": "https://example.test/verilator",
  "rules": [
    {"id": "UNUSED", "defaultSeverity": "warning", "tags": ["unused"]},
    {"id": "WIDTH", "defaultSeverity": "warning", "tags": ["width"]}
  ]
}
''';

const _veribleJson = '''
{
  "engineId": "verible",
  "displayName": "Verible",
  "helpBaseUrl": "https://example.test/verible",
  "rules": [
    {"id": "no-tabs", "defaultSeverity": "warning",
     "tags": ["style", "whitespace"],
     "helpUrl": "https://example.test/verible/no-tabs"}
  ]
}
''';

void main() {
  group('RuleDatabase.load', () {
    test('loads multiple engines from the bundle', () async {
      final bundle = _MapBundle({
        'lib/data/rules/verilator.json': _verilatorJson,
        'lib/data/rules/verible.json': _veribleJson,
      });
      final db = await RuleDatabase.load(
        engineIds: ['verilator', 'verible'],
        bundle: bundle,
      );
      expect(db.engineIds, ['verilator', 'verible']);
      expect(db.engineCount, 2);
      expect(db.ruleCount, 3);
    });

    test('silently skips engines whose asset is missing', () async {
      final bundle = _MapBundle({
        'lib/data/rules/verilator.json': _verilatorJson,
      });
      final db = await RuleDatabase.load(
        engineIds: ['verilator', 'slang'],
        bundle: bundle,
      );
      expect(db.engineIds, ['verilator']);
    });

    test(
      'rejects engine docs whose engineId mismatches the filename',
      () async {
        final bundle = _MapBundle({
          'lib/data/rules/verible.json': '{"engineId":"slang","rules":[]}',
        });
        final db = await RuleDatabase.load(
          engineIds: ['verible'],
          bundle: bundle,
        );
        expect(db.engineIds, isEmpty);
      },
    );

    test(
      'templates per-rule help URLs from helpBaseUrl with #id anchor',
      () async {
        final bundle = _MapBundle({
          'lib/data/rules/verilator.json': _verilatorJson,
        });
        final db = await RuleDatabase.load(
          engineIds: ['verilator'],
          bundle: bundle,
        );
        final rule = db.lookup('verilator/UNUSED');
        expect(rule, isNotNull);
        expect(
          rule!.helpUri.toString(),
          'https://example.test/verilator#UNUSED',
        );
      },
    );

    test('per-rule helpUrl overrides the templated default', () async {
      final bundle = _MapBundle({
        'lib/data/rules/verible.json': _veribleJson,
      });
      final db = await RuleDatabase.load(
        engineIds: ['verible'],
        bundle: bundle,
      );
      final rule = db.lookup('verible/no-tabs');
      expect(rule!.helpUri.toString(), 'https://example.test/verible/no-tabs');
    });

    test('silently ignores malformed rule entries', () async {
      const messyJson = '''
      {
        "engineId": "verilator",
        "rules": [
          {"id": "OK", "defaultSeverity": "warning"},
          {"defaultSeverity": "warning"},
          {"id": "NOSEV"},
          "not an object",
          {"id": "BADSEV", "defaultSeverity": "frobnicate"}
        ]
      }
      ''';
      final bundle = _MapBundle({
        'lib/data/rules/verilator.json': messyJson,
      });
      final db = await RuleDatabase.load(
        engineIds: ['verilator'],
        bundle: bundle,
      );
      expect(db.rulesFor('verilator'), hasLength(1));
      expect(db.rulesFor('verilator').single.id, 'verilator/OK');
    });

    test('malformed JSON yields an empty entry for that engine', () async {
      final bundle = _MapBundle({
        'lib/data/rules/verilator.json': '{ this is not json',
      });
      final db = await RuleDatabase.load(
        engineIds: ['verilator'],
        bundle: bundle,
      );
      expect(db.engineIds, isEmpty);
    });

    test(
      'non-asset errors propagate so configuration mistakes surface',
      () async {
        final bundle = _ThrowsBundle(StateError('boom'));
        await expectLater(
          () => RuleDatabase.load(engineIds: ['x'], bundle: bundle),
          throwsA(isA<StateError>()),
        );
      },
    );
  });

  group('RuleDatabase.lookup', () {
    late RuleDatabase db;
    setUp(() async {
      final bundle = _MapBundle({
        'lib/data/rules/verilator.json': _verilatorJson,
      });
      db = await RuleDatabase.load(
        engineIds: ['verilator'],
        bundle: bundle,
      );
    });

    test('returns the rule for a namespaced id', () {
      final rule = db.lookup('verilator/UNUSED');
      expect(rule, isNotNull);
      expect(rule!.id, 'verilator/UNUSED');
      expect(rule.defaultSeverity, Severity.warning);
      expect(rule.tags, ['unused']);
    });

    test('returns null for a non-namespaced id', () {
      expect(db.lookup('UNUSED'), isNull);
    });

    test('returns null for an unknown engine', () {
      expect(db.lookup('ghdl/IEEE'), isNull);
    });

    test('returns null for an unknown rule in a known engine', () {
      expect(db.lookup('verilator/DOES_NOT_EXIST'), isNull);
    });

    test('lookupBy is equivalent to lookup with the namespaced form', () {
      final a = db.lookupBy(engineId: 'verilator', localRuleId: 'UNUSED');
      final b = db.lookup('verilator/UNUSED');
      expect(a, equals(b));
    });
  });

  group('RuleDatabase bundled assets', () {
    // Verilator 5.050 accepts 123 message codes via `-Wno-<CODE>`; the
    // file was regenerated by probing every one of them against the real
    // binary. It previously carried 52 — no phantoms, but 71 codes the
    // engine can emit and the inspector had no metadata or help link for.
    test('verilator.json under lib/data/rules ships ≥ 120 rules', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final db = await RuleDatabase.load(engineIds: ['verilator']);
      expect(db.rulesFor('verilator').length, greaterThanOrEqualTo(120));
    });

    // Verilator's docs anchor each warning as `#cmdoption-arg-<CODE>`, so
    // the old `helpBaseUrl` + `#<CODE>` templating produced a link that
    // silently landed at the top of the page. Every rule now carries the
    // `verilator.org/warn/<CODE>` redirector the binary itself prints.
    test('every verilator rule has a per-rule help URL', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final db = await RuleDatabase.load(engineIds: ['verilator']);
      final rules = db.rulesFor('verilator');
      expect(rules, isNotEmpty);
      for (final rule in rules) {
        final code = rule.id.split('/').last;
        expect(
          rule.helpUri?.toString(),
          'https://verilator.org/warn/$code',
          reason: 'rule ${rule.id} has no engine-canonical help URL',
        );
      }
    });

    test('verilator rule ids are unique', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final db = await RuleDatabase.load(engineIds: ['verilator']);
      final ids = db.rulesFor('verilator').map((r) => r.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('verible.json under lib/data/rules ships ≥ 40 rules', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final db = await RuleDatabase.load(engineIds: ['verible']);
      expect(db.rulesFor('verible').length, greaterThanOrEqualTo(40));
    });

    // Slang 11.0.0 documents 246 `-W` option names, every one of which
    // was accepted by the real binary when the file was regenerated.
    test('slang.json under lib/data/rules ships ≥ 200 rules', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final db = await RuleDatabase.load(engineIds: ['slang']);
      expect(db.rulesFor('slang').length, greaterThanOrEqualTo(200));
    });

    // GHDL 6.0.0 and 5.1.1 both list exactly 38 warnings under
    // `ghdl help-warnings`.
    test('ghdl.json under lib/data/rules ships ≥ 38 rules', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final db = await RuleDatabase.load(engineIds: ['ghdl']);
      expect(db.rulesFor('ghdl').length, greaterThanOrEqualTo(38));
    });

    // The rule ids must be the engine's own vocabulary: slang reports
    // `optionName` (its `-W` name), so a PascalCase internal diagnostic
    // class name would never match a violation. Every entry in the file
    // was rejected by the real slang binary before this was fixed.
    test(
      'slang rule ids are `-W` option names, not diag class names',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        final db = await RuleDatabase.load(engineIds: ['slang']);
        final ids = db.rulesFor('slang').map((r) => r.id).toList();
        expect(ids, contains('slang/unused-variable'));
        expect(ids, contains('slang/width-trunc'));
        expect(ids, contains('slang/implicit-conv'));
        final pascalCase = ids
            .where((id) => RegExp('/[A-Z]').hasMatch(id))
            .toList();
        expect(
          pascalCase,
          isEmpty,
          reason: 'slang emits lowercase-hyphenated option names only',
        );
      },
    );

    // Same contract for GHDL: the bracketed flag in its output is
    // `[-Wunused]`, so the rule id is `unused`.
    test('ghdl rule ids match the bracketed --warn flag names', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final db = await RuleDatabase.load(engineIds: ['ghdl']);
      final ids = db.rulesFor('ghdl').map((r) => r.id).toList();
      expect(ids, contains('ghdl/unused'));
      expect(ids, contains('ghdl/hide'));
      expect(ids, contains('ghdl/binding'));
      expect(ids, contains('ghdl/reserved-word'));
    });

    test('combined rule database spans the three primary engines and '
        'crosses 100 rules total', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final db = await RuleDatabase.load(
        engineIds: ['verilator', 'verible', 'slang'],
      );
      expect(db.engineCount, 3);
      expect(db.ruleCount, greaterThanOrEqualTo(100));
    });
  });

  group('first-party rule files cover every id the engine emits', () {
    // Both ids sets are closed: CDC and Yosys rule ids are LintCrux's own,
    // written as literals in the engine sources. A literal with no rule
    // entry renders no metadata or help and is missing from the Rules panel
    // and the severity-override list.
    Set<String> literalIds(Iterable<File> sources, RegExp pattern) => {
      for (final file in sources)
        for (final m in pattern.allMatches(file.readAsStringSync()))
          m.group(1)!,
    };

    test('cdc.json lists every cdc/<id> the CDC engine emits', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final sources = Directory(
        'lib/services/engines/cdc',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.dart'));
      final emitted = literalIds(sources, RegExp("'cdc/([a-z0-9-]+)'"));
      expect(emitted, isNotEmpty);
      final db = await RuleDatabase.load(engineIds: ['cdc']);
      final shipped = {
        for (final r in db.rulesFor('cdc')) r.id.split('/').last,
      };
      expect(
        emitted.difference(shipped),
        isEmpty,
        reason: 'CDC rule ids with no cdc.json entry',
      );
    });

    test('yosys.json lists every id in the Yosys pattern table', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final engine = File('lib/services/engines/yosys/yosys_check_engine.dart');
      final table = engine.readAsStringSync();
      final start = table.indexOf('_rulePatterns');
      final end = table.indexOf('];', start);
      final emitted = literalIds(
        [engine],
        RegExp(r"\('[^']*', '([a-z0-9-]+)'\)"),
      ).where((id) => table.substring(start, end).contains("'$id'")).toSet();
      expect(emitted, isNotEmpty);
      final db = await RuleDatabase.load(engineIds: ['yosys']);
      final shipped = {
        for (final r in db.rulesFor('yosys')) r.id.split('/').last,
      };
      expect(emitted.difference(shipped), isEmpty);
    });
  });
}

class _ThrowsBundle extends CachingAssetBundle {
  _ThrowsBundle(this.error);
  final Error error;

  @override
  Future<ByteData> load(String key) async {
    Error.throwWithStackTrace(error, StackTrace.current);
  }
}
