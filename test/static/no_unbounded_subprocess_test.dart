// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The LintCrux half of a suite-wide guard.
///
/// NetCrux carries the same shape: the subprocess seam is one file, it is raced
/// against a timeout and killed on overrun, and a static guard stops a second
/// spawn site appearing beside it. LintCrux spawns *more* processes than
/// NetCrux does — seven engine families under `lib/services/engines/` — and had
/// no such guard.
///
/// The seam here is [ProcessRunner] in `process_runner.dart`, whose production
/// implementation forwards to `Process.start`, bounded by
/// `timeout_engine_watchdog.dart`. An engine that spawned its own process
/// would bypass the watchdog, so a hung `verilator` would hang the lint run
/// with nothing to cancel — and the symptom is a spinner, not an error, which
/// is why this is worth a guard rather than a review note.
///
/// Deliberately scoped to `lib/services/engines/`. Elsewhere in the app a
/// subprocess is a different thing entirely (the editor launcher opens the
/// user's `$EDITOR` and must *not* be bounded), and a repo-wide ban would have
/// to allow so much that it would stop meaning anything.
void main() {
  test('no raw Process spawn under lib/services/engines/', () {
    final dir = Directory('lib/services/engines');
    expect(dir.existsSync(), isTrue, reason: 'engines services dir must exist');

    final offenders = <String>[];
    final spawn = RegExp(r'Process\s*\.\s*(run|start|runSync)\s*\(');
    for (final file
        in dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where((f) => !f.path.endsWith('.g.dart'))) {
      final rel = p.relative(file.path);
      if (_allowed.contains(p.basename(rel))) continue;
      final source = file.readAsStringSync();
      for (final match in spawn.allMatches(source)) {
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        offenders.add('$rel:$line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'A raw Process spawn appeared under lib/services/engines/. Engine '
          'invocations go through the ProcessRunner seam in '
          'process_runner.dart, which is what timeout_engine_watchdog.dart '
          'bounds and kills — spawning directly reintroduces a lint run that '
          'cannot be cancelled.\n${offenders.join('\n')}',
    );
  });

  /// The allowlist is asserted, not just declared.
  ///
  /// An entry that stops being needed is an entry that would silently excuse a
  /// future spawn in the same file. This fails when one goes stale.
  test('every allowlisted file still spawns something', () {
    final spawn = RegExp(r'Process\s*\.\s*(run|start|runSync)\s*\(');
    for (final name in _allowed) {
      final matches = Directory('lib/services/engines')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => p.basename(f.path) == name);
      expect(
        matches,
        isNotEmpty,
        reason: '$name is allowlisted but no longer exists. Drop the entry.',
      );
      expect(
        spawn.hasMatch(matches.first.readAsStringSync()),
        isTrue,
        reason:
            '$name is allowlisted but no longer spawns a process. Drop the '
            'entry, or it will excuse the next spawn added to that file.',
      );
    }
  });
}

/// Files under `lib/services/engines/` permitted to spawn directly.
///
/// One entry. `process_runner.dart` **is** the seam — it is where the one
/// permitted `Process.start` lives. NetCrux's copy of this guard needs no
/// such entry because its seam sits in `crux_yosys`, outside the scanned
/// directory.
///
/// The Windows `reg query` that discovers installed toolchains used to be a
/// second entry here; that PATH discovery now lives in `crux_io`
/// (`engineSearchDirs`), outside the scanned directory, and the one copy
/// serves every product that spawns an engine.
const _allowed = <String>{'process_runner.dart'};
