// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/app.dart';
import 'package:lintcrux/core/cli/cli_exit_codes.dart';

/// The desktop executable's command-line-only invocations must end the
/// process. A Flutter desktop runner keeps its window and event loop alive
/// after `main` returns, so `bootstrap` printing and returning left
/// `LintCrux --version` (or a mistyped flag in a script) behind an empty
/// window with its exit code never delivered.
void main() {
  Future<int?> run(List<String> args) async {
    int? exitedWith;
    addTearDown(() => exitCode = 0);
    await runLintcrux(
      args: args,
      exitProcess: (code) async => exitedWith = code,
    );
    return exitedWith;
  }

  test('--version exits 0', () async {
    expect(await run(<String>['--version']), CliExitCode.clean);
  });

  test('--help exits 0', () async {
    expect(await run(<String>['--help']), CliExitCode.clean);
  });

  test('an unknown flag exits 64 instead of opening the app', () async {
    expect(await run(<String>['--no-such-flag']), CliExitCode.usage);
  });

  test('a failed --import-filelist exits 65', () async {
    final missing = '${Directory.systemTemp.path}/lintcrux-no-such-list.f';
    expect(
      await run(<String>['--import-filelist', missing]),
      CliExitCode.dataError,
    );
  });

  test('both entry points go through runLintcrux', () {
    // Open core here; the Pro overlay's main.dart is pinned by its own test.
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('runLintcrux('));
    expect(main, isNot(contains('=> bootstrap(')));
  });
}
