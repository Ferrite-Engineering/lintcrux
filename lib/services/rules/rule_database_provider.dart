// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/services/rules/rule_database.dart';

/// The engine ids LintCrux ships rule metadata for: one
/// `lib/data/rules/<engineId>.json` per engine in `defaultEngineRegistry()`.
///
/// A fixed list rather than the engine registry's ids, because the rule
/// database must load in the read-only web viewer, and building the
/// registry means constructing engine adapters that are free to touch
/// `dart:io` platform state — the web build has none, and a registry read
/// there once red-screened the whole viewer. A VM test holds this list
/// equal to the registry's ids, so a new engine cannot ship without its
/// rules.
const List<String> kShippedRuleDatabaseEngineIds = <String>[
  'verilator',
  'verible',
  'slang',
  'yosys',
  'ghdl',
  'svlint',
  'cdc',
];

/// Riverpod provider exposing the app-wide [RuleDatabase].
///
/// Loads rule metadata for [kShippedRuleDatabaseEngineIds] from the JSON
/// assets under `lib/data/rules/<engineId>.json`, on desktop and web alike.
/// Tests override this provider to inject a hand-built database.
///
/// The returned future is small and cheap (loads at most a handful of
/// JSON files); once resolved, the database is held in memory for the
/// app's lifetime.
final FutureProvider<RuleDatabase> ruleDatabaseProvider =
    FutureProvider<RuleDatabase>((ref) async {
      return await RuleDatabase.load(engineIds: kShippedRuleDatabaseEngineIds);
    });
