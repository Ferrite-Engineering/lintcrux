// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Shared support for the *project-level* fixture corpus under
// `test/fixtures/projects/`.
//
// This is the project-level analogue of `engine_corpus_support.dart`, and
// it exists because of a specific failure: for its whole life the corpus's
// `expected.sarif.json` files were fiction. Nothing ran an engine against
// them and nothing compared anything to them — the only test that touched
// them checked that the JSON parsed and carried `"version": "2.1.0"`. Two
// of the four were provably wrong when finally checked against real
// binaries on 2026-08-03 (see PROJECT_FIXTURES.md).
//
// The model that replaces it: every fixture commits, per engine, the exact
// subprocess invocation the engine adapter built AND the exact stdout /
// stderr / exit code the real binary produced (`engine-output/<id>.json`).
// The golden `expected.sarif.json` is then *derived* from those recordings
// by replaying them through the real engine + parser. Three consequences:
//
//   * A fabricated expectation is no longer possible without also
//     fabricating a subprocess recording, which `capture.json` forces you
//     to attribute to a named binary and version.
//   * Adapter argv drift (the `-Wall` the Verilator adapter never passed)
//     fails a test that needs no binary installed.
//   * Parser drift fails the same binary-free test.
//
// A fourth guard re-runs the real binary when it is on PATH and compares
// against the golden; that is the layer that catches an expectation which
// is merely *wrong*, as opposed to internally inconsistent.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/run.dart';
import 'package:lintcrux/domain/models/sarif_report.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/ghdl/ghdl_engine.dart';
import 'package:lintcrux/services/engines/process_runner.dart';
import 'package:lintcrux/services/engines/slang/slang_engine.dart';
import 'package:lintcrux/services/engines/svlint/svlint_engine.dart';
import 'package:lintcrux/services/engines/verible/verible_engine.dart';
import 'package:lintcrux/services/engines/verilator/verilator_engine.dart';
import 'package:lintcrux/services/project/project_file_codec.dart';
import 'package:lintcrux/services/run/engine_run_planner.dart';
import 'package:lintcrux/services/sarif/sarif_writer.dart';
import 'package:path/path.dart' as p;

/// Root of the project-fixture corpus, relative to the package root.
const String kProjectFixturesRoot = 'test/fixtures/projects';

/// Directory inside a fixture holding the per-engine subprocess
/// recordings.
const String kEngineOutputDirName = 'engine-output';

/// The per-fixture capture manifest: which binary produced each
/// recording, at which version, on what date — and, for engines the
/// capture host did not have, an explicit `unverified` reason.
const String kCaptureManifestName = 'capture.json';

/// The golden unified SARIF derived from the recordings.
const String kExpectedSarifName = 'expected.sarif.json';

/// Engine ids this corpus can capture and replay.
///
/// Every engine whose adapter drives a subprocess through
/// [ProcessRunner]. `yosys` is deliberately absent: its adapter parses via
/// the external `crux_yosys` package rather than a [ProcessRunner], so it
/// cannot be recorded by this harness. A fixture that enables it must say
/// so in [CaptureManifest.unverified].
const List<String> kCapturableEngineIds = <String>[
  'verilator',
  'verible',
  'slang',
  'ghdl',
  'svlint',
];

/// One discovered project fixture.
class ProjectFixture {
  /// Creates a [ProjectFixture].
  ProjectFixture({
    required this.name,
    required this.dir,
    required this.project,
  });

  /// Slash-separated path of the fixture below [kProjectFixturesRoot],
  /// e.g. `basic_warnings` or `vhdl/basic_warnings`. Used as the stable
  /// case name in golden run ids.
  final String name;

  /// Absolute path to the fixture directory.
  final String dir;

  /// The decoded `project.lintcrux`.
  final LintProject project;

  /// Absolute path to the golden SARIF.
  String get expectedSarifPath => p.join(dir, kExpectedSarifName);

  /// Absolute path to the capture manifest.
  String get capturePath => p.join(dir, kCaptureManifestName);

  /// Absolute path to the recording for [engineId].
  String recordingPath(String engineId) =>
      p.join(dir, kEngineOutputDirName, '$engineId.json');

  /// Engine ids the project asks for, in declaration order.
  List<String> get enabledEngineIds => project.enabledEngineIds;
}

/// Discovers every project fixture under [root], **recursively**.
///
/// Recursion is not incidental. The previous discovery walked only the
/// immediate children of `test/fixtures/projects`, so `vhdl/basic_warnings`
/// — the one fixture with a genuine engine error in it — was never
/// enumerated by any test at all.
List<ProjectFixture> discoverProjectFixtures({String? root}) {
  final rootDir = Directory(
    root ??
        p.joinAll(<String>[
          Directory.current.path,
          ...kProjectFixturesRoot.split('/'),
        ]),
  );
  if (!rootDir.existsSync()) return const <ProjectFixture>[];
  const codec = ProjectFileCodec();
  final out = <ProjectFixture>[];
  for (final entry in rootDir.listSync(recursive: true).whereType<File>()) {
    if (p.basename(entry.path) != 'project.lintcrux') continue;
    final dir = entry.parent.path;
    out.add(
      ProjectFixture(
        name: p
            .relative(dir, from: rootDir.path)
            .split(Platform.pathSeparator)
            .join('/'),
        dir: dir,
        project: codec.decode(entry.readAsStringSync()),
      ),
    );
  }
  out.sort((a, b) => a.name.compareTo(b.name));
  return out;
}

/// Builds the [LintEngine] for [engineId] bound to [projectRoot] and
/// [runner], or `null` when the id is outside [kCapturableEngineIds].
LintEngine? capturableEngine(
  String engineId, {
  required String projectRoot,
  required ProcessRunner runner,
}) {
  switch (engineId) {
    case 'verilator':
      return VerilatorEngine(runner: runner, projectRoot: projectRoot);
    case 'verible':
      return VeribleEngine(runner: runner, projectRoot: projectRoot);
    case 'slang':
      return SlangEngine(runner: runner, projectRoot: projectRoot);
    case 'ghdl':
      return GhdlEngine(runner: runner, projectRoot: projectRoot);
    case 'svlint':
      return SvlintEngine(runner: runner, projectRoot: projectRoot);
    default:
      return null;
  }
}

/// Plans the run for [fixture] exactly as the headless CLI would, and
/// returns the request each capturable engine receives.
///
/// Going through the real [EngineRunPlanner] rather than hand-building a
/// [LintRunRequest] is what makes the recorded argv meaningful: language
/// routing, per-engine options and the source-file selection are all the
/// production ones.
Map<String, LintRunRequest> planRequests(
  ProjectFixture fixture, {
  required ProcessRunner runner,
}) {
  final engines = <LintEngine>[
    for (final id in fixture.enabledEngineIds)
      if (capturableEngine(id, projectRoot: fixture.dir, runner: runner)
          case final LintEngine e)
        e,
  ];
  final plan = const EngineRunPlanner().plan(
    project: fixture.project,
    registry: EngineRegistry(engines),
    binaryConfigFor: (_) => const EngineBinaryConfig.system(),
  );
  return <String, LintRunRequest>{
    for (final pair in plan.pairs) pair.engine.id: pair.request,
  };
}

/// One recorded subprocess invocation: what the adapter asked for, and
/// what the binary answered.
class RecordedInvocation {
  /// Creates a [RecordedInvocation].
  const RecordedInvocation({
    required this.executable,
    required this.arguments,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  /// Reads a [RecordedInvocation] from its JSON form.
  factory RecordedInvocation.fromJson(Map<String, dynamic> json) =>
      RecordedInvocation(
        executable: json['executable'] as String,
        arguments: (json['arguments'] as List).cast<String>(),
        exitCode: json['exitCode'] as int,
        stdout: (json['stdout'] as List).cast<String>(),
        stderr: (json['stderr'] as List).cast<String>(),
      );

  /// The executable name the adapter resolved.
  final String executable;

  /// The full argument vector the adapter built. Compared against a live
  /// re-plan by the binary-free guard, so a silently dropped flag fails.
  final List<String> arguments;

  /// The process exit code.
  final int exitCode;

  /// Captured stdout lines.
  final List<String> stdout;

  /// Captured stderr lines.
  final List<String> stderr;

  /// JSON form written into `engine-output/<id>.json`.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'executable': executable,
    'arguments': arguments,
    'exitCode': exitCode,
    'stdout': stdout,
    'stderr': stderr,
  };
}

/// The per-engine recording set for one fixture.
class EngineRecording {
  /// Creates an [EngineRecording].
  const EngineRecording({required this.engineId, required this.invocations});

  /// Reads an [EngineRecording] from its JSON form.
  factory EngineRecording.fromJson(Map<String, dynamic> json) =>
      EngineRecording(
        engineId: json['engineId'] as String,
        invocations: <RecordedInvocation>[
          for (final i in json['invocations'] as List)
            RecordedInvocation.fromJson(i as Map<String, dynamic>),
        ],
      );

  /// The engine this recording belongs to.
  final String engineId;

  /// Every subprocess the adapter started, in order. More than one is
  /// normal — Verible and slang attempt a JSON invocation and fall back
  /// to text mode on older builds.
  final List<RecordedInvocation> invocations;

  /// JSON form.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'engineId': engineId,
    'invocations': <Map<String, dynamic>>[
      for (final i in invocations) i.toJson(),
    ],
  };
}

/// The capture manifest: provenance for the recordings, and the explicit
/// record of engines the capture host could not verify.
class CaptureManifest {
  /// Creates a [CaptureManifest].
  const CaptureManifest({
    required this.capturedAt,
    required this.host,
    required this.engineVersions,
    required this.unverified,
  });

  /// Reads a [CaptureManifest] from its JSON form.
  factory CaptureManifest.fromJson(Map<String, dynamic> json) =>
      CaptureManifest(
        capturedAt: json['capturedAt'] as String,
        host: json['host'] as String,
        engineVersions: (json['engineVersions'] as Map).map(
          (k, v) => MapEntry(k as String, v as String),
        ),
        unverified: (json['unverified'] as Map? ?? const {}).map(
          (k, v) => MapEntry(k as String, v as String),
        ),
      );

  /// ISO date the capture was taken.
  final String capturedAt;

  /// Host description (OS + arch), for reading a version-skew failure.
  final String host;

  /// Engine id → the binary's own `--version` first line.
  final Map<String, String> engineVersions;

  /// Engine id → why no recording exists. An engine that is enabled by
  /// the project and has no recording MUST appear here; the static guard
  /// fails otherwise. This is what makes "we guessed" impossible to leave
  /// undeclared.
  final Map<String, String> unverified;

  /// JSON form.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'capturedAt': capturedAt,
    'host': host,
    'engineVersions': engineVersions,
    'unverified': unverified,
  };
}

/// A [ProcessRunner] that replays [RecordedInvocation]s instead of
/// spawning anything, and records the argv it was asked for.
///
/// Spawning is an error: a replay that reaches a real binary is not a
/// replay. That is the same discipline SimCrux's example guard uses.
class PlaybackProcessRunner implements ProcessRunner {
  /// Creates a runner that will replay [invocations] in order.
  PlaybackProcessRunner(this.invocations);

  /// The recordings to replay.
  final List<RecordedInvocation> invocations;

  /// The argv of each `start` call, in order — compared against the
  /// recording so adapter flag drift fails.
  final List<List<String>> requestedArguments = <List<String>>[];

  /// The executable of each `start` call, in order.
  final List<String> requestedExecutables = <String>[];

  int _next = 0;

  @override
  Future<LintProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    requestedExecutables.add(executable);
    requestedArguments.add(List<String>.unmodifiable(arguments));
    if (_next >= invocations.length) {
      throw StateError(
        'the adapter started more subprocesses (${_next + 1}) than the '
        'recording holds (${invocations.length}) — re-capture with '
        '`dart run tool/capture_project_fixtures.dart`',
      );
    }
    return ReplayProcess(invocations[_next++]);
  }
}

/// A [LintProcess] that serves a [RecordedInvocation]'s captured streams
/// and exit code. Shared with the capture tool, which hands adapters a
/// replay of the recording it just drained so capture and replay cannot
/// diverge.
class ReplayProcess implements LintProcess {
  /// Creates a [ReplayProcess] over [_rec].
  ReplayProcess(this._rec);

  final RecordedInvocation _rec;
  final Completer<void> _stdoutDrained = Completer<void>();
  final Completer<void> _stderrDrained = Completer<void>();
  Stream<String>? _stdout;
  Stream<String>? _stderr;

  /// Emits [lines], then completes [drained].
  ///
  /// The completion is the whole point. Every adapter in this repo
  /// subscribes to both streams and then `await`s [exitCode], cancelling
  /// its subscriptions in a `finally`. A naive `Stream.fromIterable` plus
  /// an immediately-resolving `exitCode` therefore delivers a *prefix* of
  /// the recording — the adapter cancels mid-drain and parses whatever
  /// arrived, which on this corpus silently cut 3 GHDL warnings down to 1.
  /// A real subprocess cannot exit before its pipes are readable, so the
  /// replay must not either.
  Stream<String> _emit(List<String> lines, Completer<void> drained) async* {
    for (final line in lines) {
      yield line;
    }
    if (!drained.isCompleted) drained.complete();
  }

  @override
  Stream<String> get stdout => _stdout ??= _emit(_rec.stdout, _stdoutDrained);

  @override
  Stream<String> get stderr => _stderr ??= _emit(_rec.stderr, _stderrDrained);

  @override
  Future<int> get exitCode async {
    // Yield once so an adapter that subscribes immediately after `start`
    // returns has taken its streams before we decide what to wait on.
    await Future<void>.delayed(Duration.zero);
    if (_stdout != null) await _stdoutDrained.future;
    if (_stderr != null) await _stderrDrained.future;
    return _rec.exitCode;
  }

  @override
  int get pid => -1;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

/// Lowers a fixture's per-engine violations to the golden SARIF map.
///
/// Deterministic by construction: the run id is
/// `proj/<fixture>/<engineId>`, the timestamps are the Unix epoch and the
/// engine version is omitted, so the same recordings always produce the
/// same bytes on any machine.
///
/// "On any machine" is only true because every [SourceLocation] is
/// rebased onto [fixtureDir] first. [SourceLocation.file] is absolute by
/// contract — the adapters resolve the engine's relative paths against
/// the project root, which for a fixture is its own absolute directory on
/// whichever machine ran the capture. Writing that through to the golden
/// made the committed bytes depend on the checkout path (so the replay
/// guard only passed on the capture host) and baked that host's home
/// directory into a corpus we publish publicly. Relative-to-the-fixture
/// is the only form that is both portable and safe to publish.
Map<String, dynamic> buildProjectFixtureSarifMap(
  String fixtureName,
  Map<String, List<Violation>> byEngine, {
  required String fixtureDir,
}) {
  final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  final runs = <Run>[
    for (final engineId in byEngine.keys)
      Run(
        id: 'proj/$fixtureName/$engineId',
        engineId: engineId,
        engineVersion: '',
        startedAt: epoch,
        finishedAt: epoch,
        violations: <Violation>[
          for (final v in byEngine[engineId]!) _rebase(v, fixtureDir),
        ],
      ),
  ];
  return const SarifWriter().toMap(SarifReport(runs: runs));
}

/// Rewrites every path in [v] to be relative to [fixtureDir], in POSIX
/// form so the golden is byte-identical on Windows.
Violation _rebase(Violation v, String fixtureDir) => v.copyWith(
  location: _rebaseLocation(v.location, fixtureDir),
  relatedLocations: <SourceLocation>[
    for (final l in v.relatedLocations) _rebaseLocation(l, fixtureDir),
  ],
);

SourceLocation _rebaseLocation(SourceLocation l, String fixtureDir) =>
    l.copyWith(
      file: p.posix.joinAll(p.split(p.relative(l.file, from: fixtureDir))),
    );

/// Encodes [map] the way every golden in this corpus is written.
String encodeGolden(Map<String, dynamic> map) =>
    '${const JsonEncoder.withIndent('  ').convert(map)}\n';

/// Cheap PATH probe — walks PATH segments and stats each candidate.
bool onPath(String binary) {
  final pathVar = Platform.environment['PATH'] ?? '';
  for (final dir in pathVar.split(Platform.isWindows ? ';' : ':')) {
    if (File(p.join(dir, binary)).existsSync()) return true;
  }
  return false;
}

/// The binary name each engine resolves from `PATH`.
const Map<String, String> kEngineBinaryNames = <String, String>{
  'verilator': 'verilator',
  'verible': 'verible-verilog-lint',
  'slang': 'slang',
  'ghdl': 'ghdl',
  'svlint': 'svlint',
};

/// Reduces one golden SARIF `run` object to the comparable finding keys
/// `<engineId>/<ruleId>@<line>:<severity>`.
///
/// Message text is deliberately excluded: a different engine build is
/// allowed to reword a diagnostic, but a different rule id, line or
/// severity is drift the golden must be re-cut for.
Set<String> goldenFindingKeys(String engineId, Map<String, dynamic> run) {
  final out = <String>{};
  for (final result
      in (run['results'] as List? ?? const <dynamic>[])
          .cast<Map<String, dynamic>>()) {
    final locations = result['locations'] as List? ?? const <dynamic>[];
    if (locations.isEmpty) continue;
    final physical =
        (locations.first as Map<String, dynamic>)['physicalLocation']
            as Map<String, dynamic>;
    final region = physical['region'] as Map<String, dynamic>;
    final level = result['level'] as String? ?? 'warning';
    final severity = level == 'error' || level == 'note' ? level : 'warning';
    out.add(
      '$engineId/${result['ruleId']}@${region['startLine']}:$severity',
    );
  }
  return out;
}

/// Collects every violation an engine emits for [request], or rethrows
/// the adapter's failure.
Future<List<Violation>> collectViolations(
  LintEngine engine,
  LintRunRequest request,
) async => await engine.run(request).toList();
