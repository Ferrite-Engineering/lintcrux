// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_eula/crux_eula.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/app.dart';
import 'package:lintcrux/core/cli/cli_exit_codes.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/eula_test_acceptance.dart';

/// `--reset-eula` is honoured by `bootstrap`, not merely accepted by the
/// parser: it removes the persisted acceptance before anything else runs, so
/// the agreement is presented again on the launch that carried the flag.
///
/// Paired with `--version` so `bootstrap` returns before mounting the app;
/// the reset runs first either way, which is the ordering under test.
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

  Future<String?> acceptedVersion() async =>
      (await SharedPreferences.getInstance()).getString(
        kCruxEulaAcceptedVersionKey,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      ...kEulaAcceptedPrefs,
    });
  });

  test('--reset-eula forgets the accepted version', () async {
    expect(await acceptedVersion(), kCruxEulaVersion);
    expect(await run(<String>['--reset-eula', '--version']), CliExitCode.clean);
    expect(await acceptedVersion(), isNull);
  });

  test('without the flag the acceptance is kept', () async {
    expect(await run(<String>['--version']), CliExitCode.clean);
    expect(await acceptedVersion(), kCruxEulaVersion);
  });

  test('--help lists it', () async {
    final lines = <String>[];
    await IOOverrides.runZoned(
      () => run(<String>['--help']),
      stdout: () => _CapturingStdout(lines),
    );
    expect(lines.join('\n'), contains('--reset-eula'));
  });
}

/// Collects `writeln` output so `--help` can be asserted on without printing.
class _CapturingStdout implements Stdout {
  _CapturingStdout(this.lines);

  final List<String> lines;

  @override
  void writeln([Object? object = '']) => lines.add('$object');

  @override
  Future<void> flush() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
