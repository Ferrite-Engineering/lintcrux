// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/interfaces/violation_transformer.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/domain/models/waiver.dart';
import 'package:lintcrux/services/waivers/pragma_waiver_reader.dart';

/// Marks a [Violation] as suppressed when an inline `// verilator
/// lint_off RULE` block in the source covers the violation's
/// `(file, line, rule)` triple.
///
/// Open Core ships only the engine-native (pragma) waiver path; the
/// managed waiver system (with metadata, expiry, approval) is the
/// headline Pro feature.
///
/// The transformer reads the matched [PragmaWaiver] back into
/// `Violation.raw['lintcrux.pragmaWaiverSourceFile' / 'Line']` so the
/// inspector can render the "Suppressed by inline pragma at file:line"
/// notice.
class PragmaWaiverTransformer implements ViolationTransformer {
  /// Creates a [PragmaWaiverTransformer].
  const PragmaWaiverTransformer(this.rangeMap);

  /// Empty transformer — applied when the project has no source-file
  /// pragmas.
  static const PragmaWaiverTransformer empty = PragmaWaiverTransformer(
    LineRangeMap.empty,
  );

  /// Pre-computed waiver ranges for the project's source files.
  final LineRangeMap rangeMap;

  @override
  Violation transform(Violation v) {
    // Only verilator-namespaced rules can be suppressed by Verilator
    // pragmas. Other engines have their own pragma vocabularies that
    // would land here as additional transformers.
    if (!v.ruleId.startsWith('verilator/')) return v;
    final localRule = v.ruleId.substring('verilator/'.length);
    final match = rangeMap.matchFor(
      file: v.location.file,
      line: v.location.line,
      ruleLocalId: localRule,
    );
    if (match == null) return v;
    final waiver = Waiver(
      id:
          'pragma:${match.file}:${match.startLine}-${match.endLine}:'
          '${match.ruleLocalId}',
      ruleId: v.ruleId,
      filePath: match.file,
      lineStart: match.startLine,
      lineEnd: match.endLine,
      reason: 'Inline pragma `// verilator lint_off ${match.ruleLocalId}`',
      author: 'source',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
    final mergedRaw = <String, dynamic>{
      ...v.raw,
      'lintcrux.pragmaWaiverSourceFile': match.file,
      'lintcrux.pragmaWaiverSourceLine': match.startLine,
    };
    return v.copyWith(
      suppression: waiver,
      raw: mergedRaw,
      // The severity stays as-is; suppression and severity are
      // orthogonal — the table simply hides suppressed rows by
      // default per `ViolationFilter.includeSuppressed`.
      severity: v.severity,
    );
  }

  /// Convenience: returns `true` when [v] would be suppressed by this
  /// transformer. Useful for tests and the inspector pane.
  bool suppresses(Violation v) {
    return transform(v).suppression != null && v.suppression == null;
  }
}
