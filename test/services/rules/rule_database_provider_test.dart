// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/engines/default_engine_registry.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';
import 'package:lintcrux/services/rules/rule_database_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ruleDatabaseProvider', () {
    test('loads the bundled rule sets for every shipped engine', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final db = await container.read(ruleDatabaseProvider.future);
      // EVERY shipped engine must ship rule metadata.
      //
      // The loader treats a missing asset as "no metadata for this engine",
      // which is the right runtime behaviour and a terrible thing to leave
      // unasserted. An engine with no metadata renders no tags and no
      // "Learn more" in the Inspector and is invisible in the rule browser,
      // and nothing said so.
      expect(
        db.engineIds.toSet(),
        kShippedRuleDatabaseEngineIds.toSet(),
        reason:
            'engines missing rule metadata: '
            '${kShippedRuleDatabaseEngineIds.toSet().difference(db.engineIds.toSet())}',
      );
      expect(db.ruleCount, greaterThan(600));
    });

    test('the shipped id list is the registry the app runs', () {
      // The list exists so the web build never builds the registry; this
      // keeps it from drifting from what the registry actually holds.
      expect(
        kShippedRuleDatabaseEngineIds.toSet(),
        defaultEngineRegistry().engineIds.toSet(),
      );
    });

    test('loads without building the engine registry, as on the web', () async {
      // On the web any engine adapter that touches dart:io platform state
      // throws `Unsupported operation: Platform._operatingSystem`. The rule
      // database must not depend on the registry at all.
      final container = ProviderContainer(
        overrides: [
          engineRegistryProvider.overrideWith(
            (_) => throw UnsupportedError('Platform._operatingSystem'),
          ),
        ],
      );
      addTearDown(container.dispose);
      final db = await container.read(ruleDatabaseProvider.future);
      expect(db.engineIds, contains('verilator'));
    });
  });
}
