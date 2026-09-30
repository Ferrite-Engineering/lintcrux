// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Unit tests under `test/services/**` must not spawn a real OS process.
///
/// Promoted from SimCrux, where it guards the unit-test hermeticity property.
/// LintCrux needed two fixes before it could pass: the editor-launch fakes in
/// click_to_source_service_test.dart and telemetry_events_test.dart both
/// spawned coreutils `true` purely to obtain a Process handle nothing reads.
/// They return a NoopProcess now.
///
/// The failure this prevents is not a crash on the developer's machine — it is
/// a test that passes on macOS and Linux and fails on Windows, where the CI
/// matrix runs on pull requests and weekly. `true`, `echo` and friends are
/// coreutils binaries, not language features; a unit test whose outcome
/// depends on what is installed on the host is not a unit test.
///
/// Real spawns belong in `integration_test/**`, which is where the
/// binary-absent skips live.
///
/// MUTATION: adding a `Process.start(...)` / `Process.run(...)` line to any
/// `test/services/**` file makes this guard red.
void main() {
  test('no test/services file spawns a real OS process', () {
    final root = Directory('test/services');
    expect(
      root.existsSync(),
      isTrue,
      reason: 'run from the package root (cwd = lintcrux/)',
    );

    final offenders = <String>[];
    final spawnPattern = RegExp(r'Process\.(start|run|runSync)\s*\(');
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match in spawnPattern.allMatches(source)) {
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        offenders.add('${entity.path}:$line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'A unit test spawned a real OS process. Return a fake handle '
          'instead, or move the test to integration_test/** behind the '
          'binary-absent skip — found:\n${offenders.join('\n')}',
    );
  });

  /// Non-vacuity: a guard over an empty or missing tree passes for the wrong
  /// reason, and would keep passing after a directory rename.
  test('the tree this scans is actually populated', () {
    final files = Directory('test/services')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    expect(
      files.length,
      greaterThan(10),
      reason:
          'test/services/ has almost nothing in it. Either the suite moved or '
          'this guard is scanning the wrong path and passing vacuously.',
    );
  });
}
