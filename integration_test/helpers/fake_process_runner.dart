// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:lintcrux/services/engines/process_runner.dart';

/// In-memory [ProcessRunner] fake used by engine unit tests.
///
/// Tests script the subprocess by configuring [stdoutLines],
/// [stderrLines], [exitCode], and (optionally) an [onStart] throw to
/// exercise the `ProcessException` path. Every started process records
/// its executable and arguments into [invocations] so the test can
/// assert on what the engine actually invoked.
class FakeProcessRunner implements ProcessRunner {
  /// Lines the fake process emits on stdout.
  List<String> stdoutLines = const <String>[];

  /// Lines the fake process emits on stderr.
  List<String> stderrLines = const <String>[];

  /// Exit code the fake process returns after emitting its output.
  int exitCode = 0;

  /// When `true`, the returned process holds open (does not auto-
  /// complete its exit code) so tests can exercise cancellation.
  bool holdOpen = false;

  /// When non-null, [start] throws this instead of returning a process.
  /// Used to exercise the "binary not on PATH" path.
  Exception? onStartThrows;

  /// Per-invocation scripts, consumed in order. When non-empty, the Nth
  /// `start` call uses `scripts[N]` instead of the flat
  /// [stdoutLines] / [stderrLines] / [exitCode] fields (falling back to
  /// them once the list is exhausted).
  ///
  /// Needed by engines that may invoke their binary more than once in a
  /// single run — e.g. Verible's automatic text-mode retry after upstream
  /// rejects `--lint_output=jsonline`.
  final List<FakeRunScript> scripts = <FakeRunScript>[];

  /// Recorded invocations in start order.
  final List<FakeInvocation> invocations = <FakeInvocation>[];

  /// Most recently returned process, if any. Tests use this to call
  /// `kill()` and assert cancellation behavior.
  FakeLintProcess? lastProcess;

  @override
  Future<LintProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    invocations.add(
      FakeInvocation(
        executable: executable,
        arguments: List<String>.unmodifiable(arguments),
        workingDirectory: workingDirectory,
        environment: environment,
      ),
    );
    if (onStartThrows != null) {
      throw onStartThrows!;
    }
    final script = invocations.length <= scripts.length
        ? scripts[invocations.length - 1]
        : null;
    final proc = FakeLintProcess(
      stdoutLines: script?.stdout ?? stdoutLines,
      stderrLines: script?.stderr ?? stderrLines,
      exitCodeValue: script?.exitCode ?? exitCode,
      holdOpen: holdOpen,
    );
    lastProcess = proc;
    return proc;
  }
}

/// Output + exit code for ONE scripted subprocess invocation. See
/// [FakeProcessRunner.scripts].
class FakeRunScript {
  /// Creates a [FakeRunScript].
  const FakeRunScript({
    this.stdout = const <String>[],
    this.stderr = const <String>[],
    this.exitCode = 0,
  });

  /// Lines this invocation emits on stdout.
  final List<String> stdout;

  /// Lines this invocation emits on stderr.
  final List<String> stderr;

  /// Exit code this invocation returns.
  final int exitCode;
}

/// One recorded `runner.start(...)` call.
class FakeInvocation {
  /// Creates a [FakeInvocation].
  const FakeInvocation({
    required this.executable,
    required this.arguments,
    this.workingDirectory,
    this.environment,
  });

  /// Executable passed to `start`.
  final String executable;

  /// Arguments passed to `start`.
  final List<String> arguments;

  /// Working directory, if any.
  final String? workingDirectory;

  /// Environment, if any.
  final Map<String, String>? environment;
}

/// In-memory [LintProcess] that emits scripted output then completes.
///
/// Emission timing: the fake holds emission until a listener subscribes
/// to *both* [stdout] and [stderr]. This avoids the broadcast-stream
/// race where events fire before the consumer has subscribed (real
/// `Process.start` doesn't have this race because the OS buffers
/// stdout / stderr pipes).
///
/// When [holdOpen] is `true`, the fake does not complete its exit code
/// until [completeNaturally] is called. Tests use this to keep the
/// process "running" so they can exercise [kill]. Without [holdOpen],
/// the fake emits its lines, closes the streams, and completes its
/// exit code with [exitCodeValue].
class FakeLintProcess implements LintProcess {
  /// Creates a [FakeLintProcess].
  FakeLintProcess({
    this.stdoutLines = const <String>[],
    this.stderrLines = const <String>[],
    this.exitCodeValue = 0,
    this.holdOpen = false,
  }) {
    _stdoutCtrl.onListen = _onSubscribed;
    _stderrCtrl.onListen = _onSubscribed;
  }

  /// Exit code emitted on natural completion.
  final int exitCodeValue;

  /// When `true`, the fake keeps the exitCode future pending until
  /// [completeNaturally] is called or [kill] fires.
  final bool holdOpen;

  /// Scripted stdout lines.
  final List<String> stdoutLines;

  /// Scripted stderr lines.
  final List<String> stderrLines;

  int _subscriptions = 0;
  bool _drainScheduled = false;

  /// Forces the fake to complete its exit code when running in
  /// [holdOpen] mode.
  void completeNaturally() {
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(exitCodeValue);
    }
  }

  void _onSubscribed() {
    _subscriptions++;
    if (_subscriptions >= 2 && !_drainScheduled) {
      _drainScheduled = true;
      unawaited(_drain(stdoutLines, stderrLines));
    }
  }

  final StreamController<String> _stdoutCtrl =
      StreamController<String>.broadcast();
  final StreamController<String> _stderrCtrl =
      StreamController<String>.broadcast();
  final Completer<int> _exitCodeCompleter = Completer<int>();
  bool _killed = false;

  /// Whether `kill()` was invoked.
  bool get killed => _killed;

  @override
  Stream<String> get stdout => _stdoutCtrl.stream;

  @override
  Stream<String> get stderr => _stderrCtrl.stream;

  @override
  Future<int> get exitCode => _exitCodeCompleter.future;

  @override
  int get pid => -1;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    _killed = true;
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(-1);
    }
    return true;
  }

  Future<void> _drain(
    List<String> stdoutLines,
    List<String> stderrLines,
  ) async {
    await Future<void>.microtask(() {});
    stdoutLines.forEach(_stdoutCtrl.add);
    await _stdoutCtrl.close();
    stderrLines.forEach(_stderrCtrl.add);
    await _stderrCtrl.close();
    if (_killed || holdOpen) return;
    _exitCodeCompleter.complete(exitCodeValue);
  }
}
