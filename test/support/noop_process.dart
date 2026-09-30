// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

/// A `Process` that never was.
///
/// `EditorLauncher.launch` returns `Future<Process>`, and the two unit tests
/// that fake it need *a* handle to return. Both used to spawn the coreutils
/// `true` binary and hand back the result, with a comment noting that nothing
/// ever consumes it.
///
/// That worked on the developers' machines and made the fast suite depend on a
/// binary that does not exist on Windows, where LintCrux's CI matrix runs on
/// pull requests and weekly. A unit test whose outcome depends on what is
/// installed on the host is not a unit test, and
/// `test/static/no_real_process_spawn_in_unit_tests_test.dart` now says so
/// mechanically.
///
/// Every member throws rather than returning a plausible-looking default. If a
/// future caller *does* start consuming the handle, the comment above stops
/// being true, and this should fail loudly at that call site rather than
/// quietly report exit code 0.
class NoopProcess implements Process {
  /// Creates a handle that stands in for a launch nobody inspects.
  const NoopProcess();

  Never _unsupported(String member) => throw UnsupportedError(
    'NoopProcess.$member was read. This stands in for an editor launch that '
    'the code under test only awaits and discards. If that changed, use a '
    'fake that models the behaviour you now depend on.',
  );

  @override
  Future<int> get exitCode => _unsupported('exitCode');

  @override
  int get pid => _unsupported('pid');

  @override
  Stream<List<int>> get stderr => _unsupported('stderr');

  @override
  IOSink get stdin => _unsupported('stdin');

  @override
  Stream<List<int>> get stdout => _unsupported('stdout');

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      _unsupported('kill');
}
