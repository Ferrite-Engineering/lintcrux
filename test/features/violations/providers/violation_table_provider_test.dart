// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/enums/violation_view_mode.dart';
import 'package:lintcrux/domain/models/baseline_violation.dart';
import 'package:lintcrux/domain/models/lint_baseline.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/named_filter_preset.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_view_mode_provider.dart';
import 'package:lintcrux/services/baseline/current_baseline_snapshot_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';
import '../../../support/telemetry_test_store.dart';

Violation _v({
  required String engineId,
  required String rule,
  Severity severity = Severity.warning,
  String file = '/x/y.sv',
  int line = 1,
}) => Violation(
  engineId: engineId,
  ruleId: '$engineId/$rule',
  severity: severity,
  message: '$engineId $rule',
  location: SourceLocation(file: file, line: line, column: 1),
);

ProviderContainer _container(InMemoryViolationStore store) {
  return ProviderContainer(
    overrides: [
      ...telemetryDeclinedOverrides(),
      violationStoreProvider.overrideWithValue(store),
    ],
  );
}

void main() {
  group('ViolationTableNotifier', () {
    test('toggleSeverity adds and removes', () {
      final store = InMemoryViolationStore();
      final c = _container(store);
      addTearDown(c.dispose);
      c
          .read(violationTableStateProvider.notifier)
          .toggleSeverity(Severity.error);
      expect(c.read(violationTableStateProvider).severities, {Severity.error});
      c
          .read(violationTableStateProvider.notifier)
          .toggleSeverity(Severity.error);
      expect(c.read(violationTableStateProvider).severities, isEmpty);
    });

    test('toggleEngine adds and removes', () {
      final store = InMemoryViolationStore();
      final c = _container(store);
      addTearDown(c.dispose);
      c.read(violationTableStateProvider.notifier).toggleEngine('verilator');
      expect(c.read(violationTableStateProvider).engineIds, {'verilator'});
      c.read(violationTableStateProvider.notifier).toggleEngine('verilator');
      expect(c.read(violationTableStateProvider).engineIds, isEmpty);
    });

    test(
      'cycleSort flips direction on same column, resets ascending on new',
      () {
        final store = InMemoryViolationStore();
        final c = _container(store);
        addTearDown(c.dispose);
        // Initial: severity ascending.
        c
            .read(violationTableStateProvider.notifier)
            .cycleSort(ViolationTableColumn.severity);
        expect(c.read(violationTableStateProvider).sortAscending, isFalse);
        c
            .read(violationTableStateProvider.notifier)
            .cycleSort(ViolationTableColumn.severity);
        expect(c.read(violationTableStateProvider).sortAscending, isTrue);
        // New column resets to ascending.
        c
            .read(violationTableStateProvider.notifier)
            .cycleSort(ViolationTableColumn.engine);
        expect(
          c.read(violationTableStateProvider).sortColumn,
          ViolationTableColumn.engine,
        );
        expect(c.read(violationTableStateProvider).sortAscending, isTrue);
      },
    );

    test('toggleSelection / selectAll / clearSelection', () {
      final store = InMemoryViolationStore();
      final c = _container(store);
      addTearDown(c.dispose);
      final a = _v(engineId: 'a', rule: 'r');
      final b = _v(engineId: 'b', rule: 'r');
      c
          .read(violationTableStateProvider.notifier)
          .toggleSelection(ViolationTableState.idOf(a));
      expect(c.read(violationTableStateProvider).selectedRuleIds, hasLength(1));
      c.read(violationTableStateProvider.notifier).selectAll([a, b]);
      expect(c.read(violationTableStateProvider).selectedRuleIds, hasLength(2));
      c.read(violationTableStateProvider.notifier).clearSelection();
      expect(c.read(violationTableStateProvider).selectedRuleIds, isEmpty);
    });

    test('reset returns to initial state', () {
      final store = InMemoryViolationStore();
      final c = _container(store);
      addTearDown(c.dispose);
      c.read(violationTableStateProvider.notifier)
        ..toggleSeverity(Severity.error)
        ..toggleEngine('verilator')
        ..setRuleSubstring('foo')
        ..reset();
      expect(c.read(violationTableStateProvider), ViolationTableState.initial);
    });

    test('setSortColumn replaces the sort column ascending', () {
      final store = InMemoryViolationStore();
      final c = _container(store);
      addTearDown(c.dispose);
      c
          .read(violationTableStateProvider.notifier)
          .setSortColumn(ViolationTableColumn.engine);
      final s = c.read(violationTableStateProvider);
      expect(s.sortColumn, ViolationTableColumn.engine);
      expect(s.sortAscending, isTrue);
    });

    test(
      'setSort restores an explicit column + direction verbatim, unlike '
      'setSortColumn (which always resets to ascending)',
      () {
        final store = InMemoryViolationStore();
        final c = _container(store);
        addTearDown(c.dispose);
        c
            .read(violationTableStateProvider.notifier)
            .setSort(ViolationTableColumn.file, ascending: false);
        final s = c.read(violationTableStateProvider);
        expect(s.sortColumn, ViolationTableColumn.file);
        expect(s.sortAscending, isFalse);
      },
    );

    test('setSort is a no-op when the column and direction already match', () {
      final store = InMemoryViolationStore();
      final c = _container(store);
      addTearDown(c.dispose);
      final notifier = c.read(violationTableStateProvider.notifier)
        ..setSort(ViolationTableColumn.file, ascending: false);
      final before = c.read(violationTableStateProvider);
      notifier.setSort(ViolationTableColumn.file, ascending: false);
      expect(c.read(violationTableStateProvider), same(before));
    });

    test(
      "per-project retention keys off THIS tab's currentProjectProvider, "
      'not a root-scoped registry id — the state written immediately '
      'after a project loads is never lost',
      () {
        final store = InMemoryViolationStore();
        final c = ProviderContainer(
          overrides: [
            ...telemetryDeclinedOverrides(),
            violationStoreProvider.overrideWithValue(store),
          ],
        );
        addTearDown(c.dispose);

        // Filters applied with no project loaded land in the
        // "no project" retention slot.
        c.read(violationTableStateProvider.notifier).setRuleSubstring('a');
        expect(c.read(violationTableStateProvider).ruleSubstring, 'a');

        // Loading a project synchronously flips the retention slot —
        // no async gap, so a mutation applied right after `load()`
        // (the shape of session replay / workspace-tab hydration) is
        // never attributed to the wrong (or a since-discarded) id.
        c
            .read(currentProjectProvider.notifier)
            .load(const LintProject(name: 'demo', rootPath: '/proj'));
        c.read(violationTableStateProvider.notifier).setRuleSubstring('UNUSED');
        expect(c.read(violationTableStateProvider).ruleSubstring, 'UNUSED');

        // Switching to a second project starts that project's slot
        // fresh rather than inheriting the first project's filter.
        c
            .read(currentProjectProvider.notifier)
            .load(const LintProject(name: 'other', rootPath: '/proj2'));
        expect(c.read(violationTableStateProvider).ruleSubstring, isEmpty);

        // Switching back to the first project's root path restores its
        // retained state.
        c
            .read(currentProjectProvider.notifier)
            .load(const LintProject(name: 'demo', rootPath: '/proj'));
        expect(c.read(violationTableStateProvider).ruleSubstring, 'UNUSED');
      },
    );

    test('applyFromPreset copies every filter dimension', () {
      final store = InMemoryViolationStore();
      final c = _container(store);
      addTearDown(c.dispose);
      const p = NamedFilterPreset(
        name: 'p',
        severities: {Severity.error},
        engineIds: {'verilator'},
        ruleSubstring: 'WIDTH',
        fileGlob: '*.sv',
      );
      c.read(violationTableStateProvider.notifier).applyFromPreset(p);
      final s = c.read(violationTableStateProvider);
      expect(s.severities, {Severity.error});
      expect(s.engineIds, {'verilator'});
      expect(s.ruleSubstring, 'WIDTH');
      expect(s.fileGlob, '*.sv');
    });
  });

  group('visibleViolationsProvider', () {
    test('reflects store contents and updates on engine replace', () async {
      final store = InMemoryViolationStore();
      final c = _container(store);
      addTearDown(c.dispose);
      expect(c.read(visibleViolationsProvider), isEmpty);
      store.replaceFromEngine('verilator', [
        _v(engineId: 'verilator', rule: 'A'),
        _v(engineId: 'verilator', rule: 'B'),
      ]);
      // Flush microtasks twice: once to deliver the broadcast event
      // to the StreamProvider, once for Riverpod to invalidate the
      // dependent Provider.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(c.read(visibleViolationsProvider), hasLength(2));
    });

    test('applies severity filter', () async {
      final store = InMemoryViolationStore();
      final c = _container(store);
      addTearDown(c.dispose);
      store.replaceFromEngine('e', [
        _v(engineId: 'e', rule: 'A', severity: Severity.error),
        _v(engineId: 'e', rule: 'B'),
      ]);
      await Future<void>.delayed(Duration.zero);
      c
          .read(violationTableStateProvider.notifier)
          .toggleSeverity(Severity.error);
      final filtered = c.read(visibleViolationsProvider);
      expect(filtered, hasLength(1));
      expect(filtered.single.severity, Severity.error);
    });

    test('applies sort direction', () async {
      final store = InMemoryViolationStore();
      final c = _container(store);
      addTearDown(c.dispose);
      store.replaceFromEngine('e', [
        _v(engineId: 'e', rule: 'B'),
        _v(engineId: 'e', rule: 'A'),
      ]);
      await Future<void>.delayed(Duration.zero);
      c
          .read(violationTableStateProvider.notifier)
          .cycleSort(ViolationTableColumn.rule);
      // After cycle on default-active column severity: switches column
      // is treated as 'first cycle' since we cycled 'rule'. Now sorted
      // by rule ascending.
      final ordered = c
          .read(visibleViolationsProvider)
          .map((v) => v.ruleId)
          .toList();
      expect(ordered, ['e/A', 'e/B']);
    });

    test('descending sort reverses the order', () async {
      final store = InMemoryViolationStore();
      final c = _container(store);
      addTearDown(c.dispose);
      store.replaceFromEngine('e', [
        _v(engineId: 'e', rule: 'A'),
        _v(engineId: 'e', rule: 'B'),
      ]);
      await Future<void>.delayed(Duration.zero);
      c.read(violationTableStateProvider.notifier)
        ..cycleSort(ViolationTableColumn.rule)
        ..cycleSort(ViolationTableColumn.rule); // flip to descending
      final ordered = c
          .read(visibleViolationsProvider)
          .map((v) => v.ruleId)
          .toList();
      expect(ordered, ['e/B', 'e/A']);
    });
  });

  group('visibleViolationsProvider with view-mode post-filter', () {
    LintBaseline baselineWith(List<Violation> frozen) {
      return LintBaseline(
        baselineId: 'b1',
        createdAt: DateTime.utc(2026, 5, 25, 10),
        projectPath: '/tmp/p',
        frozenViolations: <BaselineViolation>[
          // No project is loaded in these containers, so the table's root
          // is empty and the fingerprint is taken over the path as reported.
          for (final v in frozen)
            BaselineViolation.fromViolation(v, projectRoot: ''),
        ],
      );
    }

    test('allViolations mode passes the filtered list through unchanged '
        '(no baseline)', () async {
      final store = InMemoryViolationStore();
      final c = _container(store);
      addTearDown(c.dispose);
      store.replaceFromEngine('e', [
        _v(engineId: 'e', rule: 'A'),
        _v(engineId: 'e', rule: 'B'),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(visibleViolationsProvider), hasLength(2));
    });

    test('allViolations mode passes the filtered list through unchanged '
        '(with baseline)', () async {
      final store = InMemoryViolationStore();
      final frozenA = _v(engineId: 'e', rule: 'A');
      final baseline = baselineWith(<Violation>[frozenA]);
      final c = ProviderContainer(
        overrides: [
          ...telemetryDeclinedOverrides(),
          violationStoreProvider.overrideWithValue(store),
          currentBaselineSnapshotProvider.overrideWithValue(baseline),
        ],
      );
      addTearDown(c.dispose);
      store.replaceFromEngine('e', [
        frozenA,
        _v(engineId: 'e', rule: 'B'),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(visibleViolationsProvider), hasLength(2));
    });

    test('onlyNew mode without a baseline still returns the filtered list '
        '(degrades to allViolations)', () async {
      final store = InMemoryViolationStore();
      final c = _container(store);
      addTearDown(c.dispose);
      c
          .read(violationViewModeProvider.notifier)
          .setMode(ViolationViewMode.onlyNew);
      store.replaceFromEngine('e', [
        _v(engineId: 'e', rule: 'A'),
        _v(engineId: 'e', rule: 'B'),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(visibleViolationsProvider), hasLength(2));
    });

    test(
      'onlyNew filters out violations matching baseline fingerprints',
      () async {
        final store = InMemoryViolationStore();
        final frozenA = _v(engineId: 'e', rule: 'A');
        final baseline = baselineWith(<Violation>[frozenA]);
        final c = ProviderContainer(
          overrides: [
            ...telemetryDeclinedOverrides(),
            violationStoreProvider.overrideWithValue(store),
            currentBaselineSnapshotProvider.overrideWithValue(baseline),
          ],
        );
        addTearDown(c.dispose);
        c
            .read(violationViewModeProvider.notifier)
            .setMode(ViolationViewMode.onlyNew);
        store.replaceFromEngine('e', [
          frozenA, // persisting
          _v(engineId: 'e', rule: 'B'), // new
        ]);
        await Future<void>.delayed(Duration.zero);
        final ruleIds = c
            .read(visibleViolationsProvider)
            .map((v) => v.ruleId)
            .toList();
        expect(ruleIds, ['e/B']);
      },
    );

    test(
      "onlyNew matches a baseline set in another checkout against this tab's "
      'project root',
      () async {
        final store = InMemoryViolationStore();
        Violation at(String root, String rule) =>
            _v(engineId: 'e', rule: rule, file: '$root/rtl/top.sv');
        final baseline = LintBaseline(
          baselineId: 'b1',
          createdAt: DateTime.utc(2026, 5, 25, 10),
          projectPath: '/Users/alice/soc',
          frozenViolations: <BaselineViolation>[
            BaselineViolation.fromViolation(
              at('/Users/alice/soc', 'A'),
              projectRoot: '/Users/alice/soc',
            ),
          ],
        );
        final c = ProviderContainer(
          overrides: [
            ...telemetryDeclinedOverrides(),
            violationStoreProvider.overrideWithValue(store),
            currentBaselineSnapshotProvider.overrideWithValue(baseline),
          ],
        );
        addTearDown(c.dispose);
        c
            .read(currentProjectProvider.notifier)
            .load(const LintProject(name: 'soc', rootPath: '/work/soc'));
        c
            .read(violationViewModeProvider.notifier)
            .setMode(ViolationViewMode.onlyNew);
        store.replaceFromEngine('e', [
          at('/work/soc', 'A'), // persisting, recorded at another path
          at('/work/soc', 'B'), // new
        ]);
        await Future<void>.delayed(Duration.zero);
        expect(
          c.read(visibleViolationsProvider).map((v) => v.ruleId).toList(),
          ['e/B'],
        );
      },
    );

    // At the 50,000-violation design point one uncached "Only new" pass is
    // about 150 million hash operations (170-370 ms measured), so a filter
    // keystroke must reuse each violation's fingerprint rather than rehash
    // it. The counter is the deterministic proxy: hashing happens once per
    // violation instance — when a run's instances first reach the table —
    // and never again while the user types.
    test('onlyNew hashes each live violation once, never per filter '
        'keystroke', () async {
      const count = 400;
      List<Violation> run() => <Violation>[
        for (var i = 0; i < count; i++)
          Violation(
            engineId: 'e',
            ruleId: i.isEven ? 'e/WIDTH' : 'e/UNUSED',
            severity: Severity.warning,
            message: 'signal s$i',
            location: SourceLocation(
              file: '/work/soc/rtl/f${i % 20}.sv',
              line: i + 1,
              column: 1,
            ),
          ),
      ];
      final first = run();
      final baseline = LintBaseline(
        baselineId: 'b1',
        createdAt: DateTime.utc(2026, 5, 25, 10),
        projectPath: '/work/soc',
        frozenViolations: <BaselineViolation>[
          for (final v in first.take(count ~/ 2))
            BaselineViolation.fromViolation(v, projectRoot: '/work/soc'),
        ],
      );
      final store = InMemoryViolationStore()..replaceFromEngine('e', first);
      final c = ProviderContainer(
        overrides: [
          ...telemetryDeclinedOverrides(),
          violationStoreProvider.overrideWithValue(store),
          currentBaselineSnapshotProvider.overrideWithValue(baseline),
        ],
      );
      addTearDown(c.dispose);
      c
          .read(currentProjectProvider.notifier)
          .load(const LintProject(name: 'soc', rootPath: '/work/soc'));
      c
          .read(violationViewModeProvider.notifier)
          .setMode(ViolationViewMode.onlyNew);

      var before = BaselineFingerprint.computeCount;
      expect(c.read(visibleViolationsProvider), hasLength(count ~/ 2));
      expect(
        BaselineFingerprint.computeCount - before,
        count,
        reason: 'the first derive hashes each live violation exactly once',
      );

      final table = c.read(violationTableStateProvider.notifier);
      for (final typed in const ['W', 'WI', 'WID', 'WIDTH', 'WIDT', '']) {
        before = BaselineFingerprint.computeCount;
        table.setRuleSubstring(typed);
        c.read(visibleViolationsProvider);
        expect(
          BaselineFingerprint.computeCount - before,
          0,
          reason: 'keystroke "$typed" rehashed live violations',
        );
      }
      before = BaselineFingerprint.computeCount;
      table.setFileGlob('*f1*');
      c.read(visibleViolationsProvider);
      expect(BaselineFingerprint.computeCount - before, 0);

      // A new run brings new instances: each is hashed once, however many
      // store events and derives it takes to land.
      table.setFileGlob('');
      before = BaselineFingerprint.computeCount;
      store.replaceFromEngine('e', run());
      await Future<void>.delayed(Duration.zero);
      expect(c.read(visibleViolationsProvider), hasLength(count ~/ 2));
      expect(BaselineFingerprint.computeCount - before, count);
    });

    test('onlyResolved returns an empty list because the table only renders '
        'live violations', () async {
      final store = InMemoryViolationStore();
      final frozenA = _v(engineId: 'e', rule: 'A');
      final baseline = baselineWith(<Violation>[frozenA]);
      final c = ProviderContainer(
        overrides: [
          ...telemetryDeclinedOverrides(),
          violationStoreProvider.overrideWithValue(store),
          currentBaselineSnapshotProvider.overrideWithValue(baseline),
        ],
      );
      addTearDown(c.dispose);
      c
          .read(violationViewModeProvider.notifier)
          .setMode(ViolationViewMode.onlyResolved);
      store.replaceFromEngine('e', [
        frozenA, // persisting
        _v(engineId: 'e', rule: 'B'), // new
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(visibleViolationsProvider), isEmpty);
    });

    test('switching the view mode notifier re-derives the visible list '
        'reactively', () async {
      final store = InMemoryViolationStore();
      final frozenA = _v(engineId: 'e', rule: 'A');
      final baseline = baselineWith(<Violation>[frozenA]);
      final c = ProviderContainer(
        overrides: [
          ...telemetryDeclinedOverrides(),
          violationStoreProvider.overrideWithValue(store),
          currentBaselineSnapshotProvider.overrideWithValue(baseline),
        ],
      );
      addTearDown(c.dispose);
      store.replaceFromEngine('e', [
        frozenA,
        _v(engineId: 'e', rule: 'B'),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(visibleViolationsProvider), hasLength(2));

      c
          .read(violationViewModeProvider.notifier)
          .setMode(ViolationViewMode.onlyNew);
      expect(
        c.read(visibleViolationsProvider).map((v) => v.ruleId).toList(),
        ['e/B'],
      );

      c
          .read(violationViewModeProvider.notifier)
          .setMode(ViolationViewMode.allViolations);
      expect(c.read(visibleViolationsProvider), hasLength(2));
    });
  });
}
