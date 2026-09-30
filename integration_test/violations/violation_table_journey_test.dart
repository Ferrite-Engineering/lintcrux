// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/violations/violation_table_journey_test.dart
//
// The core product loop, end to end in a running open-core build:
// open a fixture project → (seeded) lint run → violations render in
// the table → filter narrows the set → selecting a row surfaces the
// inspector detail pane. Violations are injected through the per-tab
// store with the real Verilator parser + the runner's transformer
// pipeline via the `seedLintRun` driver helper — no engine binaries.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lintcrux/features/inspector/widgets/inspector_pane.dart';
import 'package:lintcrux/features/source_preview/widgets/source_preview_pane.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/features/workspace/widgets/workspace_root.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/source_preview/source_preview_provider.dart';
import 'package:path/path.dart' as p;

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  disablePlatformSemantics();

  testWidgets(
    'violation-table journey: seed → filter → select → inspector',
    (tester) async {
      // Seeding the violation table trips the debug-only first-build
      // provider self-invalidation wart (PENDING.md "Known issues"). It
      // can land on a frame after the triggering line, so filter it at
      // the source rather than reaching for `takeException` later.
      tolerateKnownFirstBuildWart();
      final projectDir = Directory.systemTemp.createTempSync(
        'lintcrux_vt_journey',
      );
      addTearDown(() {
        try {
          projectDir.deleteSync(recursive: true);
        } on FileSystemException {
          // Best-effort cleanup.
        }
      });

      await bootLintcrux(tester);
      final projectPath = await createFixtureProject(
        projectDir,
        sources: {
          'rtl/top.sv': '// fixture\nmodule top; wire unused_sig; endmodule\n',
          'rtl/util.sv': '// fixture\nmodule util_mod; endmodule\n',
        },
      );
      final tab = await openFixtureProject(tester, projectPath);
      expect(visibleViolations(tab), isEmpty);
      // The resolved paths the inspector and the source preview show: the
      // platform's own separator, which on Windows is not `/`.
      final topSv = p.join(projectDir.path, 'rtl', 'top.sv');
      final utilSv = p.join(projectDir.path, 'rtl', 'util.sv');

      // Seed a completed run: three violations parsed from fixture
      // Verilator stderr by the real parser.
      const unusedLine =
          '%Warning-UNUSEDSIGNAL: rtl/top.sv:2:18: '
          "Signal is not used: 'unused_sig'";
      const declLine =
          '%Warning-DECLFILENAME: rtl/util.sv:2:8: '
          'Filename does not match module name';
      final violations = parseVerilatorFixture(projectDir.path, [
        unusedLine,
        '%Error-PINMISSING: rtl/top.sv:2:1: Cell pin is not connected: foo',
        declLine,
      ]);
      expect(violations, hasLength(3));
      await seedLintRun(tester, tab, violations: violations);

      // 1. The table renders all three rows.
      final allSeeded = await pumpUntil(
        tester,
        () => visibleViolations(tab).length == 3,
      );
      expect(allSeeded, isTrue, reason: 'seeded violations never rendered');
      expect(find.text('verilator/UNUSEDSIGNAL'), findsOneWidget);
      expect(find.text('verilator/PINMISSING'), findsOneWidget);
      expect(find.text('verilator/DECLFILENAME'), findsOneWidget);

      // 2. Filtering by rule substring narrows the visible set (the
      // search input is debounced — bounded-poll the derived list).
      final l10n = L10N.of(tester.element(find.byType(WorkspaceRoot)));
      final ruleField = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == l10n.violationFilterRuleHint,
      );
      expect(ruleField, findsOneWidget);
      await tester.enterText(ruleField, 'UNUSED');
      final narrowed = await pumpUntil(
        tester,
        () => visibleViolations(tab).length == 1,
      );
      expect(narrowed, isTrue, reason: 'rule filter never narrowed the set');
      // The derived list narrowing is not the table having repainted, so poll
      // the rows themselves before asserting the filtered-out one is gone.
      final tableNarrowed = await pumpUntil(
        tester,
        () => find.text('verilator/PINMISSING').evaluate().isEmpty,
      );
      expect(
        tableNarrowed,
        isTrue,
        reason: 'the table still showed a row the filter excluded',
      );
      expect(find.text('verilator/UNUSEDSIGNAL'), findsOneWidget);
      expect(find.text('verilator/PINMISSING'), findsNothing);

      // 3. Clearing the filter restores the full set.
      await tester.enterText(ruleField, '');
      final restored = await pumpUntil(
        tester,
        () => visibleViolations(tab).length == 3,
      );
      expect(restored, isTrue, reason: 'clearing the filter never restored');
      // Same again: the tap below needs the row back on screen, not merely
      // back in the derived list.
      final tableRestored = await pumpUntil(
        tester,
        () => find.text('verilator/PINMISSING').evaluate().length == 1,
      );
      expect(
        tableRestored,
        isTrue,
        reason: 'the table never repainted the restored rows',
      );

      // 4. Selecting a row surfaces the inspector detail pane.
      await tester.tap(find.text('verilator/PINMISSING'));
      final selected = await pumpUntil(
        tester,
        () => tab.read(selectedViolationProvider) != null,
      );
      expect(selected, isTrue, reason: 'row tap never selected');
      expect(
        tab.read(selectedViolationProvider)?.ruleId,
        'verilator/PINMISSING',
      );
      expect(find.byType(InspectorPane), findsWidgets);
      // The selection provider flips inside the tap's own frame, so the
      // poll above returns without ever pumping again and the inspector
      // is still one build behind. Poll the RENDERED chrome before
      // asserting on it — the widget, not the provider, is the claim.
      final inspectorRendered = await pumpUntil(
        tester,
        () => find.text(l10n.inspectorOpenInEditor).evaluate().length == 1,
      );
      expect(
        inspectorRendered,
        isTrue,
        reason: 'inspector never rendered the selected violation',
      );
      // Inspector-only chrome: the open-in-editor affordance and the
      // file:line:col location string.
      expect(find.text(l10n.inspectorOpenInEditor), findsOneWidget);
      expect(
        find.text('$topSv:2:1'),
        findsOneWidget,
      );

      // 5. Source-preview jump-to-source: `sourcePreviewWindowProvider`
      // (keyed off `selectedViolationProvider`) resolves a window
      // around the selected violation's location, and
      // `SourcePreviewPane` renders the file path in its header plus
      // the highlighted source line.
      final selectedViolation = tab.read(selectedViolationProvider);
      final firstWindow = await pumpUntil(
        tester,
        () =>
            tab
                .read(sourcePreviewWindowProvider(selectedViolation))
                .value
                ?.file ==
            topSv,
      );
      expect(
        firstWindow,
        isTrue,
        reason: 'source preview never resolved rtl/top.sv for PINMISSING',
      );
      final sourcePreviewPane = find.byType(SourcePreviewPane);
      // Same one-frame lag as the inspector above: the window provider
      // resolving is not the pane having painted it.
      final firstPreviewRendered = await pumpUntil(
        tester,
        () =>
            find
                .descendant(
                  of: sourcePreviewPane,
                  matching: find.text(topSv),
                )
                .evaluate()
                .length ==
            1,
      );
      expect(
        firstPreviewRendered,
        isTrue,
        reason: 'source preview never painted rtl/top.sv',
      );
      expect(
        find.descendant(
          of: sourcePreviewPane,
          matching: find.text(topSv),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sourcePreviewPane,
          matching: find.text('module top; wire unused_sig; endmodule'),
        ),
        findsOneWidget,
      );

      // 6. Selecting a different row updates the source preview to
      // that violation's file — proves the window is keyed off
      // selection, not stuck on the first pick.
      await tester.tap(find.text('verilator/DECLFILENAME'));
      final reselected = await pumpUntil(
        tester,
        () =>
            tab.read(selectedViolationProvider)?.ruleId ==
            'verilator/DECLFILENAME',
      );
      expect(reselected, isTrue, reason: 'second row tap never selected');
      final secondSelected = tab.read(selectedViolationProvider);
      final secondWindow = await pumpUntil(
        tester,
        () =>
            tab.read(sourcePreviewWindowProvider(secondSelected)).value?.file ==
            utilSv,
      );
      expect(
        secondWindow,
        isTrue,
        reason: 'source preview never updated to rtl/util.sv for DECLFILENAME',
      );
      final secondPreviewRendered = await pumpUntil(
        tester,
        () =>
            find
                .descendant(
                  of: sourcePreviewPane,
                  matching: find.text(utilSv),
                )
                .evaluate()
                .length ==
            1,
      );
      expect(
        secondPreviewRendered,
        isTrue,
        reason: 'source preview never repainted for rtl/util.sv',
      );
      expect(
        find.descendant(
          of: sourcePreviewPane,
          matching: find.text(utilSv),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sourcePreviewPane,
          matching: find.text('module util_mod; endmodule'),
        ),
        findsOneWidget,
      );

      expect(tester.takeException(), isNull);
    },
  );
}
