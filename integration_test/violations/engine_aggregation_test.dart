// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/violations/engine_aggregation_test.dart
//
// `InMemoryViolationStore.replaceFromEngine` keeps one bucket per
// engine id; the combined view (`ViolationStore.all` /
// `visibleViolationsProvider`) is the union of every engine's bucket,
// and replacing one engine's bucket never touches another engine's
// violations. This drives `seedLintRun` twice with two different
// engine ids against the same tab and asserts the table shows the
// union, then re-seeds one engine to prove the other engine's rows
// survive untouched — same boot → fixture → seed scaffolding as
// `violation_table_journey_test.dart`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  disablePlatformSemantics();

  testWidgets(
    'engine aggregation: two engines merge into the combined violation table',
    (tester) async {
      // Seeding the violation table trips the debug-only first-build
      // provider self-invalidation wart (PENDING.md "Known issues"). It
      // can land on a frame after the triggering line, so filter it at
      // the source rather than reaching for `takeException` later.
      tolerateKnownFirstBuildWart();
      final projectDir = Directory.systemTemp.createTempSync(
        'lintcrux_vt_engines',
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

      // Engine A: real Verilator-parsed fixture output (two violations).
      const unusedLine =
          '%Warning-UNUSEDSIGNAL: rtl/top.sv:2:18: '
          "Signal is not used: 'unused_sig'";
      const declLine =
          '%Warning-DECLFILENAME: rtl/util.sv:2:8: '
          'Filename does not match module name';
      final verilatorViolations = parseVerilatorFixture(projectDir.path, [
        unusedLine,
        declLine,
      ]);
      expect(verilatorViolations, hasLength(2));

      // Engine B: hand-built, distinct engine id — models a second
      // lint engine reporting on the same project (no Verible parser
      // dependency needed for this contract test).
      final veribleViolations = [
        Violation(
          engineId: 'verible',
          ruleId: 'verible/LINE_LENGTH',
          severity: Severity.note,
          message: 'Line length exceeds limit',
          location: SourceLocation(
            file: '${projectDir.path}/rtl/top.sv',
            line: 2,
            column: 1,
          ),
        ),
        Violation(
          engineId: 'verible',
          ruleId: 'verible/MODULE_FILENAME',
          severity: Severity.warning,
          message: 'Module name does not match filename',
          location: SourceLocation(
            file: '${projectDir.path}/rtl/util.sv',
            line: 2,
            column: 1,
          ),
        ),
      ];

      await seedLintRun(tester, tab, violations: verilatorViolations);
      await seedLintRun(
        tester,
        tab,
        violations: veribleViolations,
        engineId: 'verible',
      );

      // 1. The table shows the union of both engines' results.
      final unionShown = await pumpUntil(
        tester,
        () => visibleViolations(tab).length == 4,
      );
      expect(
        unionShown,
        isTrue,
        reason: 'violation table never showed the two-engine union',
      );
      expect(find.text('verilator/UNUSEDSIGNAL'), findsOneWidget);
      expect(find.text('verilator/DECLFILENAME'), findsOneWidget);
      expect(find.text('verible/LINE_LENGTH'), findsOneWidget);
      expect(find.text('verible/MODULE_FILENAME'), findsOneWidget);

      // 2. Re-seeding one engine's bucket replaces only that engine's
      // rows — the other engine's bucket is untouched (the per-engine
      // merge contract, not a flat accumulate-forever list).
      final rerunViolations = parseVerilatorFixture(projectDir.path, [
        '%Error-PINMISSING: rtl/top.sv:2:1: Cell pin is not connected: foo',
      ]);
      expect(rerunViolations, hasLength(1));
      await seedLintRun(tester, tab, violations: rerunViolations);

      final rerunShown = await pumpUntil(
        tester,
        () => visibleViolations(tab).length == 3,
      );
      expect(
        rerunShown,
        isTrue,
        reason: 're-seeding verilator never settled to 1 + 2 = 3 rows',
      );
      expect(find.text('verilator/PINMISSING'), findsOneWidget);
      expect(find.text('verilator/UNUSEDSIGNAL'), findsNothing);
      expect(find.text('verilator/DECLFILENAME'), findsNothing);
      expect(find.text('verible/LINE_LENGTH'), findsOneWidget);
      expect(find.text('verible/MODULE_FILENAME'), findsOneWidget);

      expect(tester.takeException(), isNull);
    },
  );
}
