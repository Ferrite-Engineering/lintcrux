// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/run/providers/lint_run_notifier.dart';
import 'package:lintcrux/features/workspace/providers/tab_overrides_factory.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';

/// Integration tests for the multi-tab invariant:
/// "Auto-reload behavior under multi-tab — file watcher per-tab; only
///  tabs referencing the changed source(s) re-run engines. Existing
///  waivers / severity overrides / saved filter presets preserved
///  across re-runs."
///
/// The auto-reload controller itself is wired in
/// `lib/features/auto_reload/providers/auto_reload_controller.dart`
/// and is included in the per-tab override factory, so each
/// tab gets its own watcher set. Verifying the *full* end-to-end
/// FileWatcherService → debounce → runIncremental chain requires real
/// disk I/O against a temp directory; that's a verification-doc
/// concern. These tests verify the structural multi-tab seam:
/// dispatching `runIncremental` on tab A's `LintRunNotifier` does
/// not touch tab B's store, run state, or selection.
void main() {
  group('auto-reload isolation under multi-tab', () {
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

    test('runIncremental on tab A leaves tab B store untouched', () async {
      final aId = crux.TabId.generate();
      final bId = crux.TabId.generate();
      final a = tabs.containerFor(aId);
      final b = tabs.containerFor(bId);

      const projectA = LintProject(name: 'A', rootPath: '/p/a');
      const projectB = LintProject(name: 'B', rootPath: '/p/b');
      a.read(currentProjectProvider.notifier).load(projectA);
      b.read(currentProjectProvider.notifier).load(projectB);

      // Seed each tab's store with a fixture violation so we can
      // confirm the cross-tab non-leakage on re-run.
      const vA = Violation(
        engineId: 'verilator',
        ruleId: 'verilator/A',
        severity: Severity.warning,
        message: 'a',
        location: SourceLocation(file: '/p/a/x.sv', line: 1, column: 1),
      );
      const vB = Violation(
        engineId: 'verilator',
        ruleId: 'verilator/B',
        severity: Severity.warning,
        message: 'b',
        location: SourceLocation(file: '/p/b/x.sv', line: 1, column: 1),
      );
      a.read(violationStoreProvider).replaceFromEngine('verilator', [vA]);
      b.read(violationStoreProvider).replaceFromEngine('verilator', [vB]);

      // The auto-reload controller would call runIncremental for the
      // file under projectA. The notifier short-circuits because the
      // engine registry has zero engines registered (no work to do)
      // but the call still resolves; the assertion is on store
      // isolation, not on the run pipeline outcome.
      await a.read(lintRunProvider.notifier).runIncremental(
        projectA,
        {'/p/a/x.sv'},
      );

      // Tab B's store is unchanged.
      expect(b.read(violationStoreProvider).all.length, 1);
      expect(
        b.read(violationStoreProvider).all.single.ruleId,
        'verilator/B',
      );
    });

    test(
      'severity overrides on the current project survive in the same '
      'tab across runs',
      () async {
        final tabId = crux.TabId.generate();
        final c = tabs.containerFor(tabId);
        c
            .read(currentProjectProvider.notifier)
            .load(
              const LintProject(name: 'A', rootPath: '/p/a'),
            );
        c
            .read(currentProjectProvider.notifier)
            .setSeverityOverride(
              'verilator/UNUSED',
              Severity.error,
            );
        expect(
          c.read(currentProjectProvider)!.severityOverrides['verilator/UNUSED'],
          Severity.error,
        );
        // A simulated re-run (`runIncremental`) does not touch
        // `currentProjectProvider`. The notifier returns immediately
        // because no engine is registered, but the assertion is on
        // the override surviving regardless.
        await c.read(lintRunProvider.notifier).runIncremental(
          c.read(currentProjectProvider)!,
          {'/p/a/x.sv'},
        );
        expect(
          c.read(currentProjectProvider)!.severityOverrides['verilator/UNUSED'],
          Severity.error,
        );
      },
    );

    test('LintRunNotifier instances are distinct per tab', () {
      final aId = crux.TabId.generate();
      final bId = crux.TabId.generate();
      final a = tabs.containerFor(aId);
      final b = tabs.containerFor(bId);
      final notifierA = a.read(lintRunProvider.notifier);
      final notifierB = b.read(lintRunProvider.notifier);
      expect(identical(notifierA, notifierB), isFalse);
    });
  });
}
