// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/violation_transformer.dart';
import 'package:lintcrux/domain/models/violation.dart';

/// Applies per-rule severity overrides from a project's
/// `severityOverrides` map.
///
/// When the violation's `ruleId` matches a key in the override map,
/// the violation's [Violation.severity] is replaced with the mapped
/// value and the original (engine-reported) severity is preserved in
/// `Violation.raw['lintcrux.engineSeverity']` so the inspector can
/// display the "Severity overridden to X (engine reported Y)" notice.
class SeverityOverrideTransformer implements ViolationTransformer {
  /// Creates a [SeverityOverrideTransformer] over [overrides], keyed
  /// by engine-namespaced rule id (`"verilator/UNUSEDSIGNAL"`).
  const SeverityOverrideTransformer(this.overrides);

  /// Empty transformer — applied when the project has no overrides.
  static const SeverityOverrideTransformer empty = SeverityOverrideTransformer(
    <String, Severity>{},
  );

  /// Rule-id → user-chosen severity, read from the
  /// project's `.lintcrux:severityOverrides` map; the engine config
  /// screen mutates the project file to add/remove entries.
  final Map<String, Severity> overrides;

  @override
  Violation transform(Violation v) {
    final override = overrides[v.ruleId];
    if (override == null || override == v.severity) return v;
    final mergedRaw = <String, dynamic>{
      ...v.raw,
      'lintcrux.engineSeverity': v.severity.name,
    };
    return v.copyWith(severity: override, raw: mergedRaw);
  }
}
