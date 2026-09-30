// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/custom_regex_rule.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/rules/custom_rule_evaluator.dart';

void main() {
  group('NoopCustomRuleEvaluator', () {
    test(
      'returns an empty violation list regardless of the rules supplied',
      () async {
        const evaluator = NoopCustomRuleEvaluator();
        final result = await evaluator.evaluate(
          CustomRuleEvaluationContext(
            project: const LintProject(name: 'p', rootPath: '/r'),
            rules: const [
              CustomRegexRule(
                id: 'no-todo',
                severity: Severity.warning,
                pattern: 'TODO',
                messageTemplate: 'TODO',
              ),
            ],
            readFile: (_) async => 'TODO here',
          ),
        );
        expect(result, isEmpty);
      },
    );
  });

  group('customRuleEvaluatorProvider', () {
    test('default value is NoopCustomRuleEvaluator', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(customRuleEvaluatorProvider),
        isA<NoopCustomRuleEvaluator>(),
      );
    });

    test('override replaces the default', () async {
      final container = ProviderContainer(
        overrides: [
          customRuleEvaluatorProvider.overrideWithValue(_CapturingEvaluator()),
        ],
      );
      addTearDown(container.dispose);
      final e = container.read(customRuleEvaluatorProvider);
      expect(e, isA<_CapturingEvaluator>());
      final result = await e.evaluate(
        CustomRuleEvaluationContext(
          project: const LintProject(name: 'p', rootPath: '/r'),
          rules: const [],
          readFile: (_) async => null,
        ),
      );
      // The capturing evaluator returns a sentinel empty list — same
      // shape as Noop, but we know we're hitting the override.
      expect(result, isEmpty);
      expect((e as _CapturingEvaluator).callCount, 1);
    });
  });
}

class _CapturingEvaluator implements CustomRuleEvaluator {
  int callCount = 0;

  @override
  Future<List<Violation>> evaluate(
    CustomRuleEvaluationContext context,
  ) async {
    callCount++;
    return const <Violation>[];
  }
}
