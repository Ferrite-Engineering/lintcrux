// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/cli/cli_args_parser.dart';
import 'package:lintcrux/services/cli/cli_args.dart' as launch_cli;

void main() {
  group('parseCliArgs (launch flags)', () {
    test('defaults: reset and noRestore are false', () {
      final cli = launch_cli.parseCliArgs(const []);
      expect(cli.reset, isFalse);
      expect(cli.noRestore, isFalse);
    });

    test('--reset sets reset', () {
      final cli = launch_cli.parseCliArgs(const ['--reset']);
      expect(cli.reset, isTrue);
      expect(cli.noRestore, isFalse);
    });

    test('--no-restore sets noRestore', () {
      final cli = launch_cli.parseCliArgs(const ['--no-restore']);
      expect(cli.noRestore, isTrue);
      expect(cli.reset, isFalse);
    });

    test('--reset and --no-restore compose with a positional file', () {
      final cli = launch_cli.parseCliArgs(
        const ['--reset', '--no-restore', 'project.lintcrux'],
      );
      expect(cli.reset, isTrue);
      expect(cli.noRestore, isTrue);
    });

    test('unknown flags are silently ignored by the launch-flag parser', () {
      final cli = launch_cli.parseCliArgs(const ['--foo', '--bar=baz', 'a.v']);
      expect(cli.reset, isFalse);
      expect(cli.noRestore, isFalse);
    });
  });

  group('stripLaunchFlags', () {
    test('removes --reset and --no-restore, keeps everything else', () {
      expect(
        launch_cli.stripLaunchFlags(
          const ['--reset', '--no-restore', 'a.v', '--quiet'],
        ),
        equals(['a.v', '--quiet']),
      );
    });

    test('no-op on args without launch flags', () {
      expect(
        launch_cli.stripLaunchFlags(const ['a.v', '--engine', 'verilator']),
        equals(['a.v', '--engine', 'verilator']),
      );
    });

    test('stripped output parses cleanly through the strict parser', () {
      // The whole point of stripping: `lintcrux --reset project.lintcrux`
      // must not exit 64 as an unknown-flag usage error.
      final result = CliArgsParser().parse(
        launch_cli.stripLaunchFlags(
          const ['--reset', '--no-restore', 'project.lintcrux'],
        ),
      );
      expect(result.isSuccess, isTrue);
      expect(result.args!.paths, equals(['project.lintcrux']));
    });

    test('without stripping, the strict parser rejects the launch flags', () {
      // Documents why the strip step exists; if CliArgsParser ever learns
      // these flags natively, the strip step can be retired.
      final result = CliArgsParser().parse(const ['--reset']);
      expect(result.isSuccess, isFalse);
    });
  });

  group('cliHelpText', () {
    test('mentions both launch flags', () {
      final help = launch_cli.cliHelpText();
      expect(help, contains('--no-restore'));
      expect(help, contains('--reset'));
    });
  });
}
