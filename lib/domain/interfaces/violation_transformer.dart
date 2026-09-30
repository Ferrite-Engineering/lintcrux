// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/models/violation.dart';

/// Hook for re-shaping engine-emitted violations before they land in
/// the [ViolationStore].
///
/// The open core has two transformers:
///
///   1. **Per-rule severity override** — replaces the engine-reported
///      severity with the user-configured value from
///      `.lintcrux:severityOverrides` for that rule.
///   2. **Inline-pragma waiver** — marks violations as suppressed
///      when a `// verilator lint_off RULE` block in the source covers
///      the violation's `(file, line, rule)` tuple.
///
/// Transformers are composed (left-to-right) via
/// [CompositeViolationTransformer]; the run orchestrator applies the
/// composite at violation-emit time so the store only ever sees
/// post-transform violations.
abstract class ViolationTransformer {
  /// Transform [v]. Returns the new violation (typically a
  /// [Violation.copyWith] with overridden fields). Returning the
  /// argument unchanged is the no-op.
  Violation transform(Violation v);
}

/// Composes a list of transformers into a single transformer that
/// applies each in order.
class CompositeViolationTransformer implements ViolationTransformer {
  /// Creates a [CompositeViolationTransformer] over [transformers].
  const CompositeViolationTransformer(this.transformers);

  /// Empty composite — convenience for tests / default wiring.
  static const ViolationTransformer empty = CompositeViolationTransformer(
    <ViolationTransformer>[],
  );

  /// Ordered transformers. Each receives the output of the previous.
  final List<ViolationTransformer> transformers;

  @override
  Violation transform(Violation v) {
    var current = v;
    for (final t in transformers) {
      current = t.transform(current);
    }
    return current;
  }
}
