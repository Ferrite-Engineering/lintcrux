// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/rule.dart';

/// Central rule metadata lookup.
///
/// Loads per-engine rule data from JSON asset files committed under
/// `lib/data/rules/<engineId>.json` (one file per engine: verilator,
/// verible, slang, and so on as more engines land). Each file is a
/// schema-versioned JSON document:
///
/// ```json
/// {
///   "engineId": "verilator",
///   "displayName": "Verilator",
///   "helpBaseUrl": "https://verilator.org/guide/latest/warnings.html",
///   "rules": [
///     {"id": "UNUSEDSIGNAL", "defaultSeverity": "warning",
///      "tags": ["unused", "signal"]},
///     ...
///   ]
/// }
/// ```
///
/// The `helpBaseUrl` is templated with `#<RULE_ID>` to produce a stable
/// `Rule.helpUri` per rule when the engine docs follow that anchoring
/// convention. Engines whose docs don't follow that convention will
/// land per-rule `helpUrl` overrides in the rule object itself; the
/// loader honors a per-rule `helpUrl` field whenever present.
///
/// **Localization**: `shortDescription` and `fullDescription` are
/// looked up from the ARB strings at lookup time (the inspector calls
/// [Rule.copyWith] with localized text). The rule databases carry
/// English text.
///
/// **Forward compatibility**: unknown fields in the JSON are silently
/// ignored. Missing engine files are treated as empty registries — the
/// inspector then degrades gracefully to engine-supplied message text
/// only, with no help URL or tags.
class RuleDatabase {
  /// Creates a [RuleDatabase] from an already-resolved engine
  /// definitions map. Use [RuleDatabase.load] in production to read
  /// from assets; tests construct directly.
  RuleDatabase(this._byEngine);

  /// Engine ID → ordered list of rules. The map is unmodifiable.
  final Map<String, RuleEngineEntry> _byEngine;

  /// Loads the rule database from the bundled JSON assets for
  /// [engineIds]. Engines whose asset is missing are silently
  /// skipped (the inspector degrades to engine-supplied text).
  static Future<RuleDatabase> load({
    required List<String> engineIds,
    AssetBundle? bundle,
  }) async {
    final assetBundle = bundle ?? rootBundle;
    final byEngine = <String, RuleEngineEntry>{};
    for (final id in engineIds) {
      // Dual-path resolution, and it is not optional.
      //
      // These JSON files are declared in lintcrux's own pubspec. They resolve
      // at the bare key when lintcrux IS the running app, and under
      // `packages/lintcrux/...` when it is consumed as a path dependency --
      // which is exactly what the Pro overlay does. Reading only the bare key
      // meant the rule database loaded NOTHING in every Pro build: no tags and
      // no "Learn more" in the Inspector, an empty rule browser, and an empty
      // rule universe behind the severity-override list.
      //
      // It failed silently because a missing asset is indistinguishable from
      // "this engine ships no metadata", which is a legitimate state the
      // loader has to tolerate. WaveCrux's ISA asset loader hit the same trap
      // and documents the same fix.
      final raw = await _tryLoadFirst(assetBundle, <String>[
        'lib/data/rules/$id.json',
        'packages/lintcrux/lib/data/rules/$id.json',
      ]);
      if (raw == null) continue;
      final entry = _parseEngineDoc(id, raw);
      if (entry != null) {
        byEngine[id] = entry;
      }
    }
    return RuleDatabase(Map<String, RuleEngineEntry>.unmodifiable(byEngine));
  }

  /// Returns the contents of the first loadable path, or null if none load.
  static Future<String?> _tryLoadFirst(
    AssetBundle bundle,
    List<String> paths,
  ) async {
    for (final path in paths) {
      final raw = await _tryLoad(bundle, path);
      if (raw != null) return raw;
    }
    return null;
  }

  /// Loads [path] from [bundle] and returns the contents, or `null` if
  /// the asset isn't present (Flutter raises a `FlutterError` from
  /// `package:flutter/foundation.dart`, which is an `Error` subclass —
  /// catching it directly trips an `avoid_catching_errors` lint, so we
  /// use the generic untyped catch and re-raise non-asset errors).
  static Future<String?> _tryLoad(AssetBundle bundle, String path) async {
    try {
      return await bundle.loadString(path);
    } catch (e) {
      // Asset-not-found is the expected branch here; anything else
      // (StateError, ArgumentError) we want to surface to the caller
      // so configuration mistakes don't hide as silent empty registries.
      final msg = e.toString();
      if (msg.contains('Unable to load asset')) return null;
      rethrow;
    }
  }

  /// Parse one engine JSON document.
  static RuleEngineEntry? _parseEngineDoc(String expectedId, String raw) {
    final dynamic decoded;
    try {
      decoded = json.decode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final engineId = decoded['engineId'];
    if (engineId is! String || engineId != expectedId) return null;
    final displayName = decoded['displayName'];
    final helpBaseUrl = decoded['helpBaseUrl'];
    final rulesRaw = decoded['rules'];
    if (rulesRaw is! List) return null;
    final rules = <Rule>[];
    for (final r in rulesRaw) {
      if (r is! Map<String, dynamic>) continue;
      final id = r['id'];
      final sev = r['defaultSeverity'];
      if (id is! String || sev is! String) continue;
      final severity = _parseSeverity(sev);
      if (severity == null) continue;
      final tagsRaw = r['tags'];
      final tags = tagsRaw is List
          ? tagsRaw.whereType<String>().toList(growable: false)
          : const <String>[];
      final perRuleHelp = r['helpUrl'];
      final namespaced = '$engineId/$id';
      final help = perRuleHelp is String && perRuleHelp.isNotEmpty
          ? Uri.tryParse(perRuleHelp)
          : (helpBaseUrl is String && helpBaseUrl.isNotEmpty
                ? Uri.tryParse('$helpBaseUrl#$id')
                : null);
      rules.add(
        Rule(
          id: namespaced,
          defaultSeverity: severity,
          helpUri: help,
          tags: List<String>.unmodifiable(tags),
        ),
      );
    }
    return RuleEngineEntry(
      engineId: engineId,
      displayName: displayName is String ? displayName : engineId,
      rules: List<Rule>.unmodifiable(rules),
    );
  }

  static Severity? _parseSeverity(String s) {
    switch (s.toLowerCase()) {
      case 'error':
        return Severity.error;
      case 'warning':
        return Severity.warning;
      case 'info':
      case 'note':
        return Severity.note;
      case 'fatal':
        return Severity.fatal;
      case 'none':
        return Severity.none;
      default:
        return null;
    }
  }

  /// Engine IDs known to the database, in load order.
  List<String> get engineIds => List<String>.unmodifiable(_byEngine.keys);

  /// Number of registered engines.
  int get engineCount => _byEngine.length;

  /// Total rule count across all engines.
  int get ruleCount =>
      _byEngine.values.fold<int>(0, (sum, e) => sum + e.rules.length);

  /// Look up a rule by engine-namespaced [ruleId]
  /// (e.g. `verilator/UNUSEDSIGNAL`). Returns `null` when the engine
  /// is unknown or the rule has no metadata entry.
  Rule? lookup(String ruleId) {
    final slash = ruleId.indexOf('/');
    if (slash <= 0) return null;
    final engineId = ruleId.substring(0, slash);
    final entry = _byEngine[engineId];
    if (entry == null) return null;
    for (final r in entry.rules) {
      if (r.id == ruleId) return r;
    }
    return null;
  }

  /// Convenience: look up by engine and local rule id pair.
  Rule? lookupBy({required String engineId, required String localRuleId}) {
    return lookup('$engineId/$localRuleId');
  }

  /// All rules for [engineId], in load order. Empty when the engine
  /// is unknown.
  List<Rule> rulesFor(String engineId) {
    final entry = _byEngine[engineId];
    return entry?.rules ?? const <Rule>[];
  }
}

/// One engine's rule registry slice (the per-file aggregate).
class RuleEngineEntry {
  /// Creates a [RuleEngineEntry].
  const RuleEngineEntry({
    required this.engineId,
    required this.displayName,
    required this.rules,
  });

  /// Engine ID (`verilator`, `verible`, `slang`, ...).
  final String engineId;

  /// Human-readable engine name from the JSON `displayName`.
  final String displayName;

  /// Ordered rules for this engine.
  final List<Rule> rules;
}
