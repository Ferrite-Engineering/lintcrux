// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/tabs/cli_multi_file_test.dart
//
// Verification driver for Verification Guide §6.5.2 / the CLI multi-file
// checklist bullet (`lintcrux a.lintcrux b.lintcrux` opens two tabs).
// LintCrux's CLI positional arguments are `.lintcrux` PROJECT paths (see
// `lib/app.dart` `_runCliFlow`), not raw source files — each positional
// path is opened via the real `OpenProjectInWorkspace.openProject` seam.
// The fixture projects enable only `kSeededFixtureEngineId` (a
// nonexistent engine id), so no real lint-engine binary is required —
// the assertion is on tab structure, not lint-run content.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'three .lintcrux projects on the CLI open three tabs (guide §6.5.2)',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('lintcrux_cli_multi_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final paths = <String>[];
      for (final name in const ['a', 'b', 'c']) {
        final path = await createFixtureProject(
          dir,
          name: name,
          sources: {'$name.sv': 'module $name(); endmodule\n'},
        );
        paths.add(path);
      }

      await bootLintcrux(tester, args: paths);

      // The auto-launch handler opens one tab per project after the
      // first frame.
      await pumpUntil(
        tester,
        () => tabCount(tester) == 3,
        timeout: const Duration(seconds: 20),
      );
      expect(
        tabCount(tester),
        3,
        reason: 'each CLI project path opens its own tab',
      );

      // Each tab references exactly one of the three project files.
      final opened = liveWorkspace(
        tester,
      ).tabs.map((t) => t.payload.projectPath).toSet();
      expect(opened, containsAll(paths));

      // The opened tabs mount their content and kick off the (no-op,
      // unknown-engine) run. Drain a settle window inside the body so
      // any background work completes here rather than after the test
      // returns.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      tester.takeException();
    },
  );
}
