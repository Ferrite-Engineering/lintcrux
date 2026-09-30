// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_projects/crux_projects.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/services/lint_cache/lint_run_cache_service_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/rules/custom_rule_evaluator.dart';
import 'package:lintcrux/services/waivers/waiver_store_provider.dart';

/// Multi-project state isolation.
///
/// The three per-project services lifted to `perProjectScope`
/// (`waiverStoreProvider`, `lintRunCacheServiceProvider`,
/// `customRuleEvaluatorProvider`) must give two open projects **distinct
/// instances** and **retain** each project's state across active-project
/// switches — so split-pane / many-tabs never bleed one project's waivers,
/// cache, or custom-rule evaluator into another. The active project id for
/// these three is driven by a controllable [StateProvider] overriding
/// [activeProjectIdProvider], so a test can switch the "active project"
/// deterministically without a real workspace.
///
/// `violationTableStateProvider`'s retention is a separate mechanism: it
/// is a per-TAB provider (rebound by `lintcruxTabOverridesFactory`) keyed
/// off THIS tab's own `currentProjectProvider`, not the root-scoped
/// `activeProjectIdProvider` registry concept the other three use. Keying
/// it off the registry used to be possible to reach through a real
/// project-open flow, but the registry only converges asynchronously
/// (`ProjectWorkspaceSync`), so a filter/sort mutation applied
/// synchronously right after a project loads (session replay, workspace
/// restore) could be written under a stale id and then discarded once the
/// registry caught up and rebuilt the notifier against the real one — see
/// `ViolationTableNotifier`'s class doc. Its isolation test below drives
/// `currentProjectProvider` directly instead.

/// Test-controllable active project id.
class _ActiveIdNotifier extends Notifier<String?> {
  @override
  String? build() => 'A';
  // Method (not a setter) to read uniformly with the codebase's other
  // notifier mutators.
  // ignore: use_setters_to_change_properties
  void activate(String? id) => state = id;
}

final _testActiveId = NotifierProvider<_ActiveIdNotifier, String?>(
  _ActiveIdNotifier.new,
);

ProviderContainer _container() {
  final c = ProviderContainer(
    overrides: [
      activeProjectIdProvider.overrideWith((ref) => ref.watch(_testActiveId)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void _switchTo(ProviderContainer c, String id) =>
    c.read(_testActiveId.notifier).activate(id);

void main() {
  group('per-project instance isolation + retention', () {
    test('waiverStoreProvider', () {
      final c = _container();
      _switchTo(c, 'A');
      final a = c.read(waiverStoreProvider);
      _switchTo(c, 'B');
      final b = c.read(waiverStoreProvider);
      expect(identical(a, b), isFalse, reason: 'distinct per project');
      _switchTo(c, 'A');
      expect(
        identical(c.read(waiverStoreProvider), a),
        isTrue,
        reason: 'project A instance retained',
      );
    });

    test('lintRunCacheServiceProvider', () {
      final c = _container();
      _switchTo(c, 'A');
      final a = c.read(lintRunCacheServiceProvider);
      _switchTo(c, 'B');
      final b = c.read(lintRunCacheServiceProvider);
      expect(identical(a, b), isFalse);
      _switchTo(c, 'A');
      expect(identical(c.read(lintRunCacheServiceProvider), a), isTrue);
    });

    test('customRuleEvaluatorProvider (stateless — structural isolation)', () {
      final c = _container();
      _switchTo(c, 'A');
      final a = c.read(customRuleEvaluatorProvider);
      _switchTo(c, 'B');
      final b = c.read(customRuleEvaluatorProvider);
      expect(identical(a, b), isFalse);
      _switchTo(c, 'A');
      expect(identical(c.read(customRuleEvaluatorProvider), a), isTrue);
    });
  });

  group('dashboard table state isolation + retention', () {
    test(
      'filter state does not bleed across projects and is retained — '
      "keyed off THIS tab's currentProjectProvider, not the "
      'activeProjectIdProvider registry the other three providers use',
      () {
        const projectA = LintProject(name: 'A', rootPath: '/proj/a');
        const projectB = LintProject(name: 'B', rootPath: '/proj/b');
        final c = ProviderContainer();
        addTearDown(c.dispose);

        c.read(currentProjectProvider.notifier).load(projectA);
        c.read(violationTableStateProvider.notifier).setRuleSubstring('foo');
        expect(c.read(violationTableStateProvider).ruleSubstring, 'foo');

        // Switch to project B — its table state is fresh.
        c.read(currentProjectProvider.notifier).load(projectB);
        expect(
          c.read(violationTableStateProvider).ruleSubstring,
          isNot('foo'),
          reason: 'project B must not inherit project A filter state',
        );
        c.read(violationTableStateProvider.notifier).setFileGlob('*.sv');
        expect(c.read(violationTableStateProvider).fileGlob, '*.sv');

        // Back to A — its filter is retained; B's glob did not leak.
        c.read(currentProjectProvider.notifier).load(projectA);
        expect(c.read(violationTableStateProvider).ruleSubstring, 'foo');
        expect(c.read(violationTableStateProvider).fileGlob, isNot('*.sv'));
      },
    );
  });
}
