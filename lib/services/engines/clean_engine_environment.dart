// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Environment scrubbing for engine subprocesses.
///
/// When an engine's stderr/stdout is connected to a TTY it may emit ANSI
/// color escape sequences (`\x1b[31m…\x1b[0m`). The hand-rolled engine
/// parsers do not strip ANSI, so colored output would corrupt the parsed
/// message and rule tokens. The fix lives at the **spawn layer**, not in
/// the parsers: every engine subprocess is started with `NO_COLOR=1` and
/// `TERM=dumb` injected into its environment, which every engine LintCrux
/// wraps honors by emitting plain, uncolored diagnostics.
///
/// This is applied uniformly by [SystemProcessRunner] for *every* spawn —
/// `checkAvailability` / `detectVersion`, dry runs, and the real lint run —
/// so there is no spawn path that can leak colored output to a parser. The
/// parser-level ANSI tolerance asserted in `parser_fuzz_test.dart` is
/// defense in depth: even if a future spawn path forgot to scrub, the
/// parser must not crash on residual escapes.
library;

import 'dart:io';

import 'package:crux_io/crux_io.dart';

/// Builds the environment map passed to `Process.start` for an engine
/// subprocess.
///
/// The returned map always carries `NO_COLOR=1` and `TERM=dumb`. Any
/// caller-supplied [base] entries are preserved, except that the two
/// color-suppression keys always win (a caller cannot accidentally
/// re-enable color by passing `TERM=xterm-256color`).
///
/// The map also carries an augmented `PATH` on macOS and Windows: the
/// inherited `PATH` with the platform's [engineSearchDirs] appended when
/// absent, so engines resolved by bare name (`verilator`, …) are found
/// even when LintCrux was launched from Finder/Dock (macOS) or from a
/// stale shell / installer (Windows) rather than a terminal. On Linux the
/// `PATH` is left untouched.
///
/// `Process.start` is invoked with `includeParentEnvironment: true`
/// (its default), so the parent process environment is still inherited;
/// this map is layered on top of it.
Map<String, String> cleanEngineEnvironment([Map<String, String>? base]) {
  final env = <String, String>{
    ...?base,
    // NO_COLOR is the cross-tool de-facto standard (https://no-color.org).
    'NO_COLOR': '1',
    // TERM=dumb makes tools that probe the terminal type fall back to
    // plain output even when they ignore NO_COLOR.
    'TERM': 'dumb',
  };
  final augmentedPath = _augmentedEnginePath(
    base?['PATH'] ?? Platform.environment['PATH'],
  );
  if (augmentedPath != null) env['PATH'] = augmentedPath;
  return env;
}

/// Returns [current] with the platform's [engineSearchDirs] appended when
/// missing, or `null` when nothing needs changing (Linux, or every dir is
/// already present). The dirs are only *appended*, taking lowest
/// precedence so they never shadow a user's own tooling.
String? _augmentedEnginePath(String? current) {
  final dirs = engineSearchDirs();
  if (dirs.isEmpty) return null;
  return appendMissingPathDirs(
    current ?? '',
    dirs,
    separator: Platform.isWindows ? ';' : ':',
    caseInsensitive: Platform.isWindows,
  );
}
