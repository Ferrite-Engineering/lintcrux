// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/services/engines/clean_engine_environment.dart';

/// Subprocess abstraction used by [LintEngine] implementations.
///
/// Wraps [Process] behind a narrow interface so tests can inject a
/// fake process that emits scripted stdout / stderr without forking
/// real binaries. The default implementation, [SystemProcessRunner],
/// uses `Process.start` and is what the production engines wire up.
///
/// The contract is intentionally minimal:
/// - [start] launches the executable and returns a [LintProcess] that
///   exposes stdout / stderr as line streams, an exit-code future, and
///   a kill method. Engines read it through [collectProcessOutput],
///   which drains both streams to their end; closing the returned
///   [LintProcess] is achieved by killing it or by stdout / stderr /
///   exitCode completing naturally.
/// - [start] throws [ProcessException] if the executable cannot be
///   launched (typically because it is not on `PATH`); engines
///   translate this to [EngineNotAvailableException].
// ignore: one_member_abstracts
abstract class ProcessRunner {
  /// Starts [executable] with [arguments] in [workingDirectory].
  Future<LintProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });
}

/// One running subprocess, as seen by a [LintEngine].
abstract class LintProcess {
  /// Stdout decoded as UTF-8 lines.
  Stream<String> get stdout;

  /// Stderr decoded as UTF-8 lines.
  Stream<String> get stderr;

  /// Future that completes with the process's exit code.
  Future<int> get exitCode;

  /// Process ID for diagnostics. May be -1 in fakes.
  int get pid;

  /// Sends a kill signal to the process. Returns whether the signal
  /// was accepted by the OS.
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]);
}

/// The production [ProcessRunner] — forwards to [Process.start].
class SystemProcessRunner implements ProcessRunner {
  /// Creates a [SystemProcessRunner].
  const SystemProcessRunner({this.host});

  /// The platform facts the executable is resolved against; `null` means
  /// the live process. A test hands in a Windows host with a synthetic
  /// `PATH` to prove the Windows resolution on any machine.
  final SpawnHost? host;

  /// The program [start] hands to [Process.start] for [executable], given
  /// the child's [environment].
  ///
  /// On Windows, `CreateProcess` searches the *calling* process's current
  /// directory ahead of `PATH`, and LintCrux's current directory is whatever
  /// shell launched it: for a developer, the repository being linted. A
  /// `verible-verilog-lint.exe` committed to that repository would win. So a
  /// bare name is resolved to an absolute path against the child's `PATH`
  /// first, and one that nothing on `PATH` answers to throws the same
  /// [ProcessException] a missing binary does, which the engines already
  /// report as "not installed". Nothing is started. Off Windows the name is
  /// returned unchanged: `execvp` never consults the current directory.
  String spawnExecutableFor(
    String executable, {
    required Map<String, String> environment,
  }) => (host ?? SpawnHost.current()).requireExecutable(
    executable,
    childEnvironment: environment,
  );

  @override
  Future<LintProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    // Scrub the engine environment so TTY-detecting engines emit plain,
    // uncolored diagnostics the parsers can read (the NO_COLOR contract).
    // Built first because it also carries the augmented `PATH` the
    // executable must be resolved against.
    final env = cleanEngineEnvironment(environment);
    final exe = spawnExecutableFor(executable, environment: env);
    final process = await Process.start(
      exe,
      arguments,
      workingDirectory: workingDirectory,
      environment: env,
    );
    return _SystemLintProcess(process);
  }
}

class _SystemLintProcess implements LintProcess {
  _SystemLintProcess(this._process)
    // `allowMalformed: true` so invalid UTF-8 byte sequences in engine
    // output (truncated multibyte chars, binary noise) decode to the
    // replacement character instead of throwing a `FormatException` that
    // would crash the whole run.
    : stdout = _process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .asBroadcastStream(),
      stderr = _process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .asBroadcastStream();

  final Process _process;

  @override
  final Stream<String> stdout;

  @override
  final Stream<String> stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  int get pid => _process.pid;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    return _process.kill(signal);
  }
}

/// How long [collectProcessOutput] keeps reading after the process exits.
///
/// Normally both pipes reach end-of-file with the process, so this never
/// comes into play. It bounds one case: a child the engine spawned outlives
/// it and still holds the inherited pipes open. Waiting on those without a
/// bound would hang the run, and a cancel of the run, until that child exits.
const Duration kEngineOutputDrainGrace = Duration(seconds: 5);

/// Everything one engine subprocess wrote, and how it exited.
class CapturedProcessOutput {
  /// Creates a [CapturedProcessOutput].
  const CapturedProcessOutput({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  /// The process exit code.
  final int exitCode;

  /// Every stdout line, in order, through end-of-file.
  final List<String> stdout;

  /// Every stderr line, in order, through end-of-file.
  final List<String> stderr;
}

/// Reads [process] to completion: its exit code AND all of its output.
///
/// The exit code and the output reach Dart on separate channels, and nothing
/// orders them. `exitCode` routinely completes while the last lines — often
/// the only lines, for an engine that prints one error and quits — are still
/// in flight. A caller that stops reading at the exit loses them, and a lint
/// engine that loses its output reports a clean run. So this waits for BOTH
/// streams to end, not for the exit.
///
/// Both streams are subscribed before the exit is awaited, so a chatty child
/// can never stall on a full pipe.
///
/// Throws [EngineRunFailedException] for [engineId] rather than returning
/// output it cannot vouch for: when a stream is still open [drainGrace] after
/// the exit, or when reading a stream failed. Either way the captured output
/// may be missing findings, and reporting it as a completed run would be a
/// false clean.
Future<CapturedProcessOutput> collectProcessOutput(
  LintProcess process, {
  required String engineId,
  required String executable,
  Duration drainGrace = kEngineOutputDrainGrace,
}) async {
  final stdout = _LineDrain(process.stdout);
  final stderr = _LineDrain(process.stderr);
  try {
    final exitCode = await process.exitCode;
    final drained = await Future.wait(<Future<void>>[
      stdout.done,
      stderr.done,
    ]).then((_) => true).timeout(drainGrace, onTimeout: () => false);

    List<String> excerpt() => <String>[
      ...stdout.lines,
      ...stderr.lines,
    ].where((l) => l.trim().isNotEmpty).take(10).toList(growable: false);

    if (!drained) {
      final grace = drainGrace.inSeconds >= 1
          ? '${drainGrace.inSeconds} s'
          : '${drainGrace.inMilliseconds} ms';
      throw EngineRunFailedException(
        engineId: engineId,
        exitCode: exitCode,
        reason:
            'exited $exitCode but its output was still open $grace later, '
            'so its findings may be incomplete',
        outputExcerpt: excerpt(),
        resolvedPath: executable,
      );
    }
    final readError = stdout.error ?? stderr.error;
    if (readError != null) {
      throw EngineRunFailedException(
        engineId: engineId,
        exitCode: exitCode,
        reason:
            'exited $exitCode but reading its output failed '
            '($readError), so its findings may be incomplete',
        outputExcerpt: excerpt(),
        resolvedPath: executable,
      );
    }
    return CapturedProcessOutput(
      exitCode: exitCode,
      stdout: stdout.lines,
      stderr: stderr.lines,
    );
  } finally {
    // A no-op for a stream that ended; releases one that outlived the grace.
    await stdout.cancel();
    await stderr.cancel();
  }
}

/// One output stream read to its end.
class _LineDrain {
  _LineDrain(Stream<String> stream) {
    _subscription = stream.listen(
      lines.add,
      onError: (Object e, StackTrace _) {
        error ??= e;
        _finish();
      },
      onDone: _finish,
      cancelOnError: true,
    );
  }

  final List<String> lines = <String>[];
  final Completer<void> _done = Completer<void>();
  late final StreamSubscription<String> _subscription;

  /// The first read error, if the stream failed rather than ended.
  Object? error;

  /// Completes when the stream has ended, cleanly or with an error.
  Future<void> get done => _done.future;

  void _finish() {
    if (!_done.isCompleted) _done.complete();
  }

  Future<void> cancel() => _subscription.cancel();
}
