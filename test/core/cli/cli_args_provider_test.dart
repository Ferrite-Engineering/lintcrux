// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/cli/cli_args.dart';
import 'package:lintcrux/core/cli/cli_args_provider.dart';

void main() {
  group('cliArgsProvider', () {
    test('defaults to CliArgs.empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(cliArgsProvider), CliArgs.empty);
    });

    test('can be overridden by the bootstrap pipeline', () {
      const override = CliArgs(
        paths: ['a.v'],
        sarifOutputPath: 'out.sarif',
        exitCodeOnFindings: true,
      );
      final container = ProviderContainer(
        overrides: [cliArgsProvider.overrideWithValue(override)],
      );
      addTearDown(container.dispose);
      expect(container.read(cliArgsProvider), override);
    });
  });
}
