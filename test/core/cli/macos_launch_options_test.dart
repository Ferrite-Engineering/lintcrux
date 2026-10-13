// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/cli/cli_args_parser.dart';
import 'package:lintcrux/core/cli/macos_launch_options.dart';

void main() {
  group('stripMacosLaunchOptions', () {
    test('removes each -Apple option together with its value', () {
      expect(
        stripMacosLaunchOptions(const <String>[
          '-AppleLanguages',
          '(ko)',
          '-AppleLocale',
          'ko_KR',
          'design.lintcrux',
        ]),
        <String>['design.lintcrux'],
      );
    });

    test('removes -NS options and the process serial number', () {
      expect(
        stripMacosLaunchOptions(const <String>[
          '-psn_0_12345',
          'design.lintcrux',
          '-NSDocumentRevisionsDebugMode',
          'YES',
        ]),
        <String>['design.lintcrux'],
      );
    });

    test('a value that looks like an option is still the value', () {
      // Each macOS option takes exactly one value, so the token after it is
      // never read as another option.
      expect(
        stripMacosLaunchOptions(const <String>[
          '-AppleLanguages',
          '-NSWhatever',
          '--exit-code',
        ]),
        <String>['--exit-code'],
      );
    });

    test('a trailing option with no value is dropped alone', () {
      expect(
        stripMacosLaunchOptions(const <String>['a.sv', '-AppleLocale']),
        <String>['a.sv'],
      );
    });

    test("LintCrux's own flags and positionals pass through unchanged", () {
      const args = <String>[
        '--no-restore',
        '--reset-eula',
        '-c',
        'overlay.lintcrux',
        '--top',
        'top',
        'a.sv',
        '-apple-not-an-option',
        '--Apple',
      ];
      expect(stripMacosLaunchOptions(args), args);
    });

    test('what macOS passes then parses as a plain launch', () {
      final result = CliArgsParser().parse(
        stripMacosLaunchOptions(const <String>[
          '-AppleLanguages',
          '(ko)',
          '-AppleLocale',
          'ko_KR',
        ]),
      );
      expect(result.isSuccess, isTrue, reason: result.error);
      expect(result.args!.paths, isEmpty);
    });
  });
}
