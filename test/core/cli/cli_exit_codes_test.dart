// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/cli/cli_exit_codes.dart';

void main() {
  group('CliExitCode', () {
    test('every code is distinct', () {
      expect(CliExitCode.all.toSet().length, CliExitCode.all.length);
    });

    test('the contract values are pinned', () {
      // These are a published interface: a CI workflow branches on the
      // literal numbers, and the docs site and the marketing site both
      // print them. Changing one is a breaking change for every pipeline
      // that already uses it, so it must break this test first.
      expect(CliExitCode.clean, 0);
      expect(CliExitCode.violations, 1);
      expect(CliExitCode.newViolations, 2);
      expect(CliExitCode.runFailed, 3);
      expect(CliExitCode.usage, 64);
      expect(CliExitCode.dataError, 65);
    });

    test('usage and dataError match the GUI front door', () {
      // `bootstrap` in lib/app.dart has always returned 64 for a parse
      // error and 65 for a failed --import-filelist. The headless binary
      // must not disagree with the app it ships beside.
      expect(CliExitCode.usage, 64, reason: 'EX_USAGE');
      expect(CliExitCode.dataError, 65, reason: 'EX_DATAERR');
    });

    test('labelFor covers every code and is stable', () {
      expect(CliExitCode.labelFor(CliExitCode.clean), 'clean');
      expect(CliExitCode.labelFor(CliExitCode.violations), 'violations');
      expect(
        CliExitCode.labelFor(CliExitCode.newViolations),
        'new-violations',
      );
      expect(CliExitCode.labelFor(CliExitCode.runFailed), 'run-failed');
      expect(
        CliExitCode.labelFor(CliExitCode.overThreshold),
        'over-threshold',
      );
      expect(CliExitCode.labelFor(CliExitCode.usage), 'usage-error');
      expect(CliExitCode.labelFor(CliExitCode.dataError), 'data-error');
    });

    test('labelFor degrades gracefully on an unknown code', () {
      expect(CliExitCode.labelFor(99), 'unknown');
    });
  });
}
