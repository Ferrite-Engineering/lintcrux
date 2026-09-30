// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_projects/crux_projects.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderFamily;
import 'package:lintcrux/domain/models/custom_regex_rule.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:meta/meta.dart';

/// Synthetic engine id under which custom-regex-rule violations are stored.
///
/// Custom rules are not a real lint engine, but their matched violations
/// land in the [ViolationStore] the same way an engine's do — under this
/// pseudo-engine slice (`ViolationStore.replaceFromEngine(kCustomRuleEngineId,
/// …)`). Every violation an evaluator emits carries `engineId ==
/// kCustomRuleEngineId` and a `ruleId` namespaced as `'$kCustomRuleEngineId/…'`,
/// so the violation table groups custom rules together and the run pipeline
/// can replace the whole custom slice on each run without touching real
/// engines. Open-core owns the constant because the run pipeline
/// (`LintRunNotifier`) references it when it stores the evaluator's output;
/// the Pro evaluator aliases it so the two never drift.
const String kCustomRuleEngineId = 'custom';

/// Inputs supplied to a [CustomRuleEvaluator] during a lint run.
///
/// The data shapes are intentionally minimal — the evaluator implementation
/// (Pro overlay) reads only what it needs and may load additional context
/// out-of-band (e.g. file contents) via [readFile].
@immutable
class CustomRuleEvaluationContext {
  /// Creates a context.
  const CustomRuleEvaluationContext({
    required this.project,
    required this.rules,
    required this.readFile,
    this.elaboratedSignalNames = const <String>[],
    this.identifierDefinitions = const <String>[],
  });

  /// The active project; the evaluator reads [LintProject.sourceFiles]
  /// and [LintProject.rootPath] from this.
  final LintProject project;

  /// Rules to evaluate. Typically [project].customRegexRules but the
  /// open-core caller passes them explicitly so the evaluator does not
  /// need to know about the project model's field name.
  final List<CustomRegexRule> rules;

  /// Reads the source bytes (as a UTF-8 string) for a file path. The
  /// open-core caller injects a function that wraps `File.readAsString`;
  /// tests inject a fake. Returns `null` when the file does not exist or
  /// cannot be read so the evaluator can skip it without crashing.
  final Future<String?> Function(String absoluteFilePath) readFile;

  /// Signal names from the elaborated design, when available. Empty until
  /// elaboration is wired in; populated then for the `signalName` pattern
  /// kind.
  final List<String> elaboratedSignalNames;

  /// Identifier names from the elaborated design (modules, instances,
  /// ports, params), when available. Empty until elaboration is wired in;
  /// populated alongside [elaboratedSignalNames].
  final List<String> identifierDefinitions;
}

/// Open-core extension point through which the Pro overlay
/// contributes the active custom-regex-rule evaluator.
///
/// The interface returns a [Future] of violations so an implementation
/// can do filesystem I/O (read every source file) without blocking the
/// main isolate. The open-core default returns an empty list — the
/// custom-regex-rule *capability* is open-core (data model, parsing,
/// provider seam) but the *evaluator implementation* is a Pro feature.
// The Pro overlay subclasses this; the abstract class is the seam.
// ignore: one_member_abstracts
abstract class CustomRuleEvaluator {
  /// Evaluates [context]'s rules and returns the matched violations.
  ///
  /// Implementations MUST NEVER crash the lint engine on bad input —
  /// invalid regex, missing files, unreadable bytes all surface as
  /// either skipped rules or internal violations tagged with the rule
  /// id and the failure mode.
  Future<List<Violation>> evaluate(CustomRuleEvaluationContext context);
}

/// Open-core no-op evaluator. Returns an empty list.
///
/// Registered as the default for [customRuleEvaluatorProvider] so an
/// open-core build with `customRegexRules` in its `.lintcrux` opens
/// without error but produces no violations from those rules. The Pro
/// overlay's `proOverrides` replaces this with the real evaluator.
class NoopCustomRuleEvaluator implements CustomRuleEvaluator {
  /// Singleton instance — every consumer gets the same reference.
  const NoopCustomRuleEvaluator();

  @override
  Future<List<Violation>> evaluate(
    CustomRuleEvaluationContext context,
  ) async => const <Violation>[];
}

/// Internal per-project family providing one [CustomRuleEvaluator] per
/// active project id.
///
/// The open-core [NoopCustomRuleEvaluator] is stateless, so per-project
/// isolation is structural only (each project resolves its own instance);
/// the lift exists for uniformity with the other per-project services and
/// so the Pro overlay's evaluator is scoped the same way. A fresh
/// (non-const) instance per project id keeps the scoping observable.
final ProviderFamily<CustomRuleEvaluator, String>
customRuleEvaluatorPerProjectFamily =
    Provider.family<CustomRuleEvaluator, String>(
      // Non-const on purpose: a fresh instance per project id makes the
      // per-project scoping observable by identity (a const would canonicalize
      // to one shared instance).
      // ignore: prefer_const_constructors
      (ref, projectId) => NoopCustomRuleEvaluator(),
      name: 'customRuleEvaluatorPerProject',
    );

/// Provider exposing the active [CustomRuleEvaluator].
///
/// Open-core default is [NoopCustomRuleEvaluator]; the Pro overlay
/// overrides this with the real implementation. Lifted to
/// [perProjectScope] for uniformity with the other
/// per-project services.
final Provider<CustomRuleEvaluator> customRuleEvaluatorProvider =
    perProjectScope<CustomRuleEvaluator>(
      'custom_rule_evaluator',
      (ref, projectId) =>
          ref.watch(customRuleEvaluatorPerProjectFamily(projectId)),
    );
