// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Capture tool for the project-level fixture corpus under
// `test/fixtures/projects/`.
//
// Runs the REAL engine binaries over each fixture through the REAL engine
// adapters, records every subprocess invocation (argv + stdout + stderr +
// exit code), and derives `expected.sarif.json` from what actually came
// back. Nothing here is written by hand — that was the failure mode this
// corpus is recovering from.
//
// Run from the lintcrux package root:
//
//   dart run tool/capture_project_fixtures.dart
//
// Engines that are not on PATH are skipped and recorded in the fixture's
// `capture.json` under `unverified`, with the reason. That entry is not
// cosmetic: `project_fixture_golden_test.dart` fails a fixture whose
// project enables an engine that has neither a recording nor an
// `unverified` reason, so an unverifiable expectation cannot be committed
// silently.
//
// Options:
//   --fixture <name>   capture only the named fixture (e.g. vhdl/basic_warnings)
//   --keep-unverified  preserve existing `unverified` entries for engines
//                      that are still missing (the default)
//   --replay           run no binary: re-derive `expected.sarif.json` from the
//                      committed recordings, leaving `engine-output/` and
//                      `capture.json` untouched. For a SARIF writer or parser
//                      change, where the engines' output has not moved.
import 'dart:convert';
import 'dart:io';

import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/process_runner.dart';
import 'package:path/path.dart' as p;

import '../test/fixtures/project_fixture_support.dart';

/// A [ProcessRunner] that spawns for real, drains the subprocess to
/// completion, records it, and then hands the adapter a *replay* of the
/// recording rather than the live process.
///
/// The obvious implementation — tee the live streams to a buffer and pass
/// the live process through — is subtly wrong, and was wrong here first.
/// [LintProcess] exposes broadcast streams; the recorder subscribes inside
/// `start`, the adapter subscribes after the `await` on `start` returns,
/// and any line that lands in between reaches the recorder but not the
/// adapter. The golden would then be built from strictly less output than
/// the recording holds, and replaying that recording would produce a
/// different SARIF — a corpus that fails its own guard, non-
/// deterministically.
///
/// Draining first makes capture-time and replay-time byte-identical by
/// construction: the adapter consumes exactly the bytes that get
/// committed. Every adapter in this repo already batches its output before
/// parsing, so nothing observable is lost by delivering it at once.
class _RecordingRunner implements ProcessRunner {
  _RecordingRunner(this.inner);

  final ProcessRunner inner;
  final List<RecordedInvocation> recorded = <RecordedInvocation>[];

  @override
  Future<LintProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final proc = await inner.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    final stdoutFuture = proc.stdout.toList();
    final stderrFuture = proc.stderr.toList();
    final code = await proc.exitCode;
    final invocation = RecordedInvocation(
      executable: executable,
      arguments: List<String>.unmodifiable(arguments),
      exitCode: code,
      stdout: await stdoutFuture,
      stderr: await stderrFuture,
    );
    recorded.add(invocation);
    return ReplayProcess(invocation);
  }
}

/// Deletes the build artifacts an engine leaves behind in a fixture
/// directory, so a capture always starts from the same state the first
/// capture started from.
///
/// This is not tidiness. GHDL's `-a` writes a work library
/// (`work-obj93.cf`) plus an object file next to the source, and it
/// *reads* that library on the next run: analysing `design.vhd` a second
/// time with the library still present adds a fourth diagnostic,
///
/// ```text
/// design.vhd:18:1:warning: entity "design" was also defined in file
/// ".../design.vhd" [-Wlibrary]
/// ```
///
/// which the first run cannot produce. Both artifacts are gitignored, so
/// the difference is invisible in `git status` — running this tool twice
/// in a row silently produced two different goldens, and only the one
/// captured on a freshly-cloned tree was correct. A derived golden whose
/// value depends on whether the deriver had run before is not a guard.
void _purgeEngineArtifacts(String fixtureDir) {
  final dir = Directory(fixtureDir);
  if (!dir.existsSync()) return;
  for (final entry in dir.listSync().whereType<File>()) {
    final name = p.basename(entry.path);
    final isGhdlWorkLibrary =
        name.startsWith('work-obj') && name.endsWith('.cf');
    if (isGhdlWorkLibrary || p.extension(name) == '.o') {
      entry.deleteSync();
    }
  }
}

/// Re-derives [fixture]'s golden from its committed recordings, exactly as
/// `project_fixture_golden_test.dart` replays them, without spawning
/// anything. A re-capture would also re-record every engine, so on a host
/// missing one binary it would turn that engine's recording into an
/// `unverified` entry just to pick up a SARIF shape change.
Future<void> _replay(ProjectFixture fixture) async {
  stdout.writeln('── ${fixture.name} (replay)');
  final byEngine = <String, List<Violation>>{};
  for (final engineId in fixture.enabledEngineIds) {
    final file = File(fixture.recordingPath(engineId));
    if (!file.existsSync()) continue;
    final recording = EngineRecording.fromJson(
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
    );
    final runner = PlaybackProcessRunner(recording.invocations);
    final request = planRequests(fixture, runner: runner)[engineId];
    if (request == null) {
      throw StateError(
        'the run planner routes no source to $engineId in ${fixture.name}, '
        'but a recording exists; re-capture instead of replaying',
      );
    }
    final engine = capturableEngine(
      engineId,
      projectRoot: fixture.dir,
      runner: runner,
    )!;
    byEngine[engineId] = await collectViolations(engine, request);
    stdout.writeln('   $engineId: ${byEngine[engineId]!.length} violation(s)');
  }
  File(fixture.expectedSarifPath).writeAsStringSync(
    encodeGolden(
      buildProjectFixtureSarifMap(
        fixture.name,
        byEngine,
        fixtureDir: fixture.dir,
      ),
    ),
  );
}

Future<String?> _detectVersion(String engineId, String projectRoot) async {
  final engine = capturableEngine(
    engineId,
    projectRoot: projectRoot,
    runner: const SystemProcessRunner(),
  );
  if (engine == null) return null;
  return await engine.detectVersion(const EngineBinaryConfig.system());
}

Future<void> main(List<String> args) async {
  final only = args.contains('--fixture')
      ? args[args.indexOf('--fixture') + 1]
      : null;

  final fixtures = discoverProjectFixtures().where(
    (f) => only == null || f.name == only,
  );
  if (fixtures.isEmpty) {
    stderr.writeln('no project fixtures matched');
    exitCode = 1;
    return;
  }

  if (args.contains('--replay')) {
    for (final fixture in fixtures) {
      await _replay(fixture);
    }
    stdout.writeln('done');
    return;
  }

  final host =
      '${Platform.operatingSystem} '
      '${Platform.version.split(' ').last.replaceAll(RegExp('[()"]'), '')}';
  final capturedAt = DateTime.now().toUtc().toIso8601String().split('T').first;

  for (final fixture in fixtures) {
    stdout.writeln('── ${fixture.name}');
    final outDir = Directory(p.join(fixture.dir, kEngineOutputDirName));
    if (outDir.existsSync()) outDir.deleteSync(recursive: true);
    _purgeEngineArtifacts(fixture.dir);

    final versions = <String, String>{};
    final unverified = <String, String>{};
    final byEngine = <String, List<Violation>>{};

    for (final engineId in fixture.enabledEngineIds) {
      if (!kCapturableEngineIds.contains(engineId)) {
        unverified[engineId] =
            'the $engineId adapter does not drive a ProcessRunner, so this '
            'harness cannot record it';
        stdout.writeln('   $engineId: not capturable');
        continue;
      }
      final binary = kEngineBinaryNames[engineId]!;
      if (!onPath(binary)) {
        unverified[engineId] =
            '$binary was not on PATH of the capture host, so no output was '
            'recorded and this engine contributes nothing to the golden';
        stdout.writeln('   $engineId: NOT ON PATH — recorded as unverified');
        continue;
      }

      final recorder = _RecordingRunner(const SystemProcessRunner());
      final requests = planRequests(fixture, runner: recorder);
      final request = requests[engineId];
      if (request == null) {
        unverified[engineId] =
            'the run planner routed no compatible source file to this engine';
        stdout.writeln('   $engineId: no compatible sources');
        continue;
      }
      final engine = capturableEngine(
        engineId,
        projectRoot: fixture.dir,
        runner: recorder,
      )!;

      List<Violation> violations;
      try {
        violations = await collectViolations(engine, request);
      } on EngineRunFailedException catch (e) {
        stderr.writeln('   $engineId: run failed — ${e.reason}');
        rethrow;
      }
      byEngine[engineId] = violations;
      versions[engineId] = (await _detectVersion(engineId, fixture.dir)) ?? '';

      outDir.createSync(recursive: true);
      File(fixture.recordingPath(engineId)).writeAsStringSync(
        encodeGolden(
          EngineRecording(
            engineId: engineId,
            invocations: recorder.recorded,
          ).toJson(),
        ),
      );
      stdout.writeln(
        '   $engineId: ${violations.length} violation(s), '
        '${recorder.recorded.length} invocation(s)',
      );
    }

    File(fixture.capturePath).writeAsStringSync(
      encodeGolden(
        CaptureManifest(
          capturedAt: capturedAt,
          host: host,
          engineVersions: versions,
          unverified: unverified,
        ).toJson(),
      ),
    );
    File(fixture.expectedSarifPath).writeAsStringSync(
      encodeGolden(
        buildProjectFixtureSarifMap(
          fixture.name,
          byEngine,
          fixtureDir: fixture.dir,
        ),
      ),
    );
  }
  stdout.writeln('done');
}
