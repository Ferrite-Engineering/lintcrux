// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:meta/meta.dart';

/// Kind of pattern surface a [CustomRegexRule] targets.
///
/// Each kind has its own scanning strategy implemented by the active
/// `CustomRuleEvaluator`:
///   * [sourceText] — line-by-line scan of every source file in the
///     project that survives the rule's `filePathGlob` filter.
///   * [signalName] — scan the elaborated design's signal name list.
///   * [identifier] — scan identifier definitions (modules, instances,
///     ports, params).
///
/// Authors who want to scan a different surface in the future add a new
/// kind here and update the evaluator.
enum CustomRulePatternKind {
  /// Scan the raw source text line by line.
  sourceText,

  /// Scan signal names in the elaborated design.
  signalName,

  /// Scan identifier definitions.
  identifier,
}

/// A user-authored project-scoped lint rule expressed as a named regex.
///
/// Custom regex rules are declared in the `customRegexRules` section of
/// the project's `.lintcrux` file. The active `CustomRuleEvaluator`
/// reads them, compiles the [pattern] on first use, scans the surface
/// declared by [patternKind], and emits a [Violation] per match with
/// the [messageTemplate] substituted.
///
/// Tier note: the *capability* (data model + parsing + provider seam)
/// lives in open-core. The *evaluator implementation* is a Pro feature
/// — under open-core builds the default [NoopCustomRuleEvaluator]
/// emits nothing, so a `.lintcrux` file with `customRegexRules:` opens
/// fine but its rules produce no violations.
@immutable
class CustomRegexRule {
  /// Creates a custom rule.
  const CustomRegexRule({
    required this.id,
    required this.severity,
    required this.pattern,
    required this.messageTemplate,
    this.patternKind = CustomRulePatternKind.sourceText,
    this.filePathGlob,
    this.enabled = true,
  });

  /// Stable rule identifier. Surfaces in the violation table as the
  /// rule id (engine-namespaced — by convention `'custom/<id>'` so it
  /// sorts alongside engine-emitted rules). Authors may pick any
  /// non-empty string; the evaluator does not enforce namespacing.
  final String id;

  /// Severity emitted for every match.
  final Severity severity;

  /// The regex source. Compiled lazily on first evaluation. Invalid
  /// patterns surface as an internal violation tagged "lint engine:
  /// custom rule `'<id>'` has invalid regex" and the rule is disabled
  /// for the run — they NEVER crash the lint engine.
  final String pattern;

  /// What surface the rule scans. Defaults to [CustomRulePatternKind.sourceText].
  final CustomRulePatternKind patternKind;

  /// Message template for the emitted violation. Supports three
  /// placeholders substituted at violation time:
  ///   * `{match}` — the matched substring.
  ///   * `{file}` — the file the match was found in.
  ///   * `{line}` — the 1-based line number of the match.
  /// Placeholder substitution is a literal `String.replaceAll`; the
  /// evaluator does not parse the template.
  final String messageTemplate;

  /// Optional glob (using shell-style `*` / `?` semantics) restricting
  /// which files the rule applies to. `null` means "every file in the
  /// project". The same matcher the waiver system uses
  /// is reused by convention so author expectations are consistent.
  final String? filePathGlob;

  /// `false` disables evaluation of this rule for the run. Lets authors
  /// keep a rule declaration in the project file while temporarily
  /// silencing it.
  final bool enabled;

  /// Returns a copy with the supplied overrides applied.
  CustomRegexRule copyWith({
    String? id,
    Severity? severity,
    String? pattern,
    CustomRulePatternKind? patternKind,
    String? messageTemplate,
    String? filePathGlob,
    bool? enabled,
  }) {
    return CustomRegexRule(
      id: id ?? this.id,
      severity: severity ?? this.severity,
      pattern: pattern ?? this.pattern,
      patternKind: patternKind ?? this.patternKind,
      messageTemplate: messageTemplate ?? this.messageTemplate,
      filePathGlob: filePathGlob ?? this.filePathGlob,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CustomRegexRule) return false;
    return other.id == id &&
        other.severity == severity &&
        other.pattern == pattern &&
        other.patternKind == patternKind &&
        other.messageTemplate == messageTemplate &&
        other.filePathGlob == filePathGlob &&
        other.enabled == enabled;
  }

  @override
  int get hashCode => Object.hash(
    id,
    severity,
    pattern,
    patternKind,
    messageTemplate,
    filePathGlob,
    enabled,
  );

  @override
  String toString() =>
      'CustomRegexRule(id: $id, severity: $severity, kind: $patternKind, '
      'glob: $filePathGlob, enabled: $enabled)';
}
