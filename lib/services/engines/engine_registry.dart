// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/interfaces/lint_engine.dart';

/// In-memory registry of all available [LintEngine] implementations,
/// keyed by [LintEngine.id].
///
/// Open-core populates this at startup with the engines compiled into the
/// binary (Verilator, Verible, Slang, Yosys, GHDL, Svlint, CDC). The Pro
/// overlay layers additional engines on top via its `proOverrides`. The
/// registry is immutable once constructed — engines do not appear or disappear
/// at runtime within a session.
///
/// Tests construct a registry with a tailored engine subset; production
/// builds the registry via `defaultEngineRegistry()`.
class EngineRegistry {
  /// Creates an [EngineRegistry] from [engines]. Throws [ArgumentError]
  /// if any two engines share the same [LintEngine.id].
  EngineRegistry(List<LintEngine> engines)
    : _engines = _buildIndex(engines, growable: false),
      _order = List<String>.unmodifiable(engines.map((e) => e.id));

  static Map<String, LintEngine> _buildIndex(
    List<LintEngine> engines, {
    required bool growable,
  }) {
    final map = <String, LintEngine>{};
    for (final e in engines) {
      if (map.containsKey(e.id)) {
        throw ArgumentError(
          'duplicate engine id "${e.id}" in EngineRegistry',
        );
      }
      map[e.id] = e;
    }
    return growable ? map : Map<String, LintEngine>.unmodifiable(map);
  }

  final Map<String, LintEngine> _engines;
  final List<String> _order;

  /// Stable insertion-order list of engine IDs.
  List<String> get engineIds => _order;

  /// All registered engines in insertion order.
  List<LintEngine> get engines =>
      List<LintEngine>.unmodifiable(_order.map((id) => _engines[id]!));

  /// Returns the engine for [id], or `null` if unregistered.
  LintEngine? get(String id) => _engines[id];

  /// Whether an engine with [id] is registered.
  bool contains(String id) => _engines.containsKey(id);

  /// Total count of registered engines.
  int get length => _engines.length;
}
