// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:lintcrux/core/cli/lintcrux_cli.dart';

/// The headless `lintcrux` binary.
///
/// Deliberately thin: everything testable lives in
/// [LintcruxCli] under `lib/`, so the CI behavior is covered by
/// `flutter test` rather than only by spawning processes. This file owns
/// exactly the two things a `lib/` file must not: reading the real
/// argument vector, and calling [exit].
///
/// Build it with:
///
/// ```bash
/// dart build cli -t bin/lintcrux.dart -o build/cli
/// # single self-contained executable:
/// build/cli/bundle/bin/lintcrux --help
/// ```
///
/// (`dart compile exe` refuses to run while any package in the
/// resolution declares a build hook — `objective_c`, pulled in
/// transitively by `path_provider_foundation`, does. `dart build cli`
/// is the supported replacement; the executable it emits under
/// `bundle/bin/` runs standalone, and `tool/build_cli.sh` wraps the
/// invocation.)
Future<void> main(List<String> args) async {
  final cli = LintcruxCli();
  final code = await cli.run(
    args,
    stdoutSink: stdout.writeln,
    stderrSink: stderr.writeln,
  );
  // Flush before exiting: `exit()` does not wait for buffered stdout,
  // and a CI log missing its summary line because the process raced the
  // pipe is a genuinely miserable thing to debug.
  await stdout.flush();
  await stderr.flush();
  exit(code);
}
