// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/issue_reporter/providers/issue_session_context.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/workspace/providers/tab_overrides_factory.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/run/lint_run_lifecycle.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';

void main() {
  Violation buildViolation({
    String ruleId = 'verilator/UNUSED',
    String engineId = 'verilator',
    Severity severity = Severity.warning,
    String file = '/p/x.sv',
    int line = 1,
  }) {
    return Violation(
      engineId: engineId,
      ruleId: ruleId,
      severity: severity,
      message: 'unused',
      location: SourceLocation(file: file, line: line, column: 1),
    );
  }

  test('lintcruxTabOverridesFactory returns a non-empty override list', () {
    final overrides = lintcruxTabOverridesFactory(crux.TabId.generate());
    expect(overrides, isNotEmpty);
  });

  test(
    'the beta issue reporter session snapshot is per-tab, not root-scoped',
    () {
      // The scope-leak class: the contributor reads `currentProjectProvider`
      // / `violationStoreProvider` / the table state, all per-tab. Left at
      // root it would resolve the empty root-scope instances, and every bug
      // report would claim "no project loaded, 0 violations" while the user
      // stares at a full violations table.
      // The root container carries the same open-core binding `bootstrap()`
      // spreads, so this compares two real bindings rather than a bound tab
      // against an unwired root.
      final root = ProviderContainer(
        overrides: [
          cruxIssueSessionContextProvider.overrideWith(
            buildLintcruxIssueSessionContext,
          ),
        ],
      );
      addTearDown(root.dispose);
      final tabs = crux.TabContainerManager(
        rootContainer: root,
        overridesFactory: lintcruxTabOverridesFactory,
      );
      addTearDown(tabs.dispose);

      final tab = tabs.containerFor(crux.TabId.generate());
      const project = LintProject(name: 'A', rootPath: '/p/a');
      tab.read(currentProjectProvider.notifier).load(project);
      tab.read(violationStoreProvider).replaceFromEngine('verilator', [
        buildViolation(),
      ]);

      String valueOf(ProviderContainer c, String label) => c
          .read(cruxIssueSessionContextProvider)
          .fields
          .firstWhere((f) => f.label == label)
          .value;

      expect(valueOf(tab, 'Project loaded'), 'yes');
      expect(valueOf(tab, 'Violations total'), '1');
      // The root container still sees an empty session — which is exactly
      // what the tab binding exists to avoid reporting.
      expect(valueOf(root, 'Project loaded'), 'no');
      expect(valueOf(root, 'Violations total'), '0');
    },
  );

  group('per-tab provider isolation under crux.TabContainerManager', () {
    late ProviderContainer root;
    late crux.TabContainerManager tabs;

    setUp(() {
      root = ProviderContainer();
      tabs = crux.TabContainerManager(
        rootContainer: root,
        overridesFactory: lintcruxTabOverridesFactory,
      );
    });

    tearDown(() {
      tabs.dispose();
      root.dispose();
    });

    test(
      'currentProjectProvider isolation: mutation in tab A does not leak '
      'into tab B',
      () {
        final aId = crux.TabId.generate();
        final bId = crux.TabId.generate();
        final a = tabs.containerFor(aId);
        final b = tabs.containerFor(bId);
        const projectA = LintProject(name: 'A', rootPath: '/p/a');
        a.read(currentProjectProvider.notifier).load(projectA);
        expect(a.read(currentProjectProvider)?.name, 'A');
        expect(b.read(currentProjectProvider), isNull);
      },
    );

    test(
      'violationStoreProvider isolation: two tabs hold distinct stores',
      () {
        final aId = crux.TabId.generate();
        final bId = crux.TabId.generate();
        final a = tabs.containerFor(aId);
        final b = tabs.containerFor(bId);
        final storeA = a.read(violationStoreProvider);
        final storeB = b.read(violationStoreProvider);
        expect(identical(storeA, storeB), isFalse);
        storeA.replaceFromEngine('verilator', [buildViolation()]);
        expect(storeA.all.length, 1);
        expect(storeB.all.length, 0);
      },
    );

    test(
      'violationTableStateProvider isolation: filter chip toggle in tab A '
      'does not affect tab B',
      () {
        final aId = crux.TabId.generate();
        final bId = crux.TabId.generate();
        final a = tabs.containerFor(aId);
        final b = tabs.containerFor(bId);
        a
            .read(violationTableStateProvider.notifier)
            .toggleSeverity(Severity.error);
        expect(
          a.read(violationTableStateProvider).severities,
          {Severity.error},
        );
        expect(b.read(violationTableStateProvider).severities, isEmpty);
      },
    );

    test(
      'selectedViolationProvider isolation: tab A selection invisible to '
      'tab B',
      () {
        final aId = crux.TabId.generate();
        final bId = crux.TabId.generate();
        final a = tabs.containerFor(aId);
        final b = tabs.containerFor(bId);
        final v = buildViolation();
        // Push into tab A's store so the selection-clears-on-invisible
        // logic keeps the selection.
        a.read(violationStoreProvider).replaceFromEngine('verilator', [v]);
        a.read(selectedViolationProvider.notifier).select(v);
        expect(a.read(selectedViolationProvider), equals(v));
        expect(b.read(selectedViolationProvider), isNull);
      },
    );

    test(
      'tabIdProvider override is applied so each container reports its own '
      'tab id',
      () {
        final aId = crux.TabId.generate();
        final bId = crux.TabId.generate();
        final a = tabs.containerFor(aId);
        final b = tabs.containerFor(bId);
        expect(a.read(crux.tabIdProvider), equals(aId));
        expect(b.read(crux.tabIdProvider), equals(bId));
      },
    );

    test(
      'lintRunLifecycleBusProvider isolation: two tabs hold distinct buses, '
      'and each differs from the root bus',
      () {
        final aId = crux.TabId.generate();
        final bId = crux.TabId.generate();
        final a = tabs.containerFor(aId);
        final b = tabs.containerFor(bId);
        final busA = a.read(lintRunLifecycleBusProvider);
        final busB = b.read(lintRunLifecycleBusProvider);
        final rootBus = root.read(lintRunLifecycleBusProvider);
        // Per-tab isolation is what keeps one tab's run-completion from
        // triggering another tab's trend dispatcher against the wrong
        // violation store (the "records zero data points" defect).
        expect(identical(busA, busB), isFalse);
        expect(identical(busA, rootBus), isFalse);
        expect(identical(busB, rootBus), isFalse);
      },
    );
  });

  group('extraTabOverridesProvider', () {
    test('open-core default is an empty override list', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(extraTabOverridesProvider), isEmpty);
    });
  });
}
