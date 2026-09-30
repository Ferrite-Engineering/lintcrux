// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/process_runner.dart';

import 'project_fixture_support.dart';

/// Guards for the project-level fixture corpus.
///
/// **Why this file exists.** Until 2026-08-03 the `expected.sarif.json`
/// files under `test/fixtures/projects/` were never compared to anything.
/// The only test that opened them (`fixture_integration_test.dart`)
/// asserted that the JSON parsed and that `version` was `"2.1.0"`. Any
/// syntactically valid SARIF passed — including two files that were
/// provably wrong:
///
///   * `projects/basic_warnings` claimed `verilator/UNUSEDSIGNAL` and
///     `verilator/UNDRIVEN`. Verilator produced neither. The fixture's own
///     line-2 comment began with the word "Verilator", which the binary
///     reads as a metacomment pragma; it aborted with
///     `%Error-BADVLTPRAGMA` before linting anything. Two further layers
///     stood behind that: the adapter never passed `-Wall` (so those two
///     checks were off regardless), and the signal was named `unused_sig`,
///     which Verilator's default `--unused-regexp '*unused*'` suppresses.
///   * `projects/vhdl/basic_warnings` claimed 2 GHDL results at lines 24
///     and 27. GHDL 6.0.0 produced 5, at different lines, with different
///     text, including a hard `type of prefix is not an array` error the
///     expected file did not mention. That fixture was not even
///     *discovered* by the old harness, which walked only the immediate
///     children of `projects/`.
///
/// **The mechanism that replaces "nobody checked".** Four layers, three of
/// which need no engine binary installed:
///
///   1. `argv` — re-plan each fixture through the real [EngineRunPlanner]
///      and assert the adapter builds the exact argument vector that was
///      recorded. A dropped `-Wall` fails here, in engine-less CI.
///   2. `replay` — feed the recorded stdout/stderr/exit code back through
///      the real adapter and parser and assert the SARIF equals the
///      golden. Parser drift fails here, in engine-less CI.
///   3. `attribution` — every engine a fixture enables must have either a
///      recording or an explicit `unverified` reason in `capture.json`.
///      This is what makes an unverifiable expectation impossible to
///      commit silently, which is the actual failure being fixed.
///   4. `live` — when the binary IS on PATH, re-run it and compare the
///      finding set to the golden. This is the only layer that can catch
///      an expectation that is merely *wrong*, so it must not be the only
///      layer, because it is also the only one that can skip.
///
/// Refresh the corpus after an intentional change with:
///
///   dart run tool/capture_project_fixtures.dart
void main() {
  final fixtures = discoverProjectFixtures();

  test('the corpus is non-empty and discovery reaches nested fixtures', () {
    expect(fixtures, isNotEmpty);
    final names = fixtures.map((f) => f.name).toSet();
    expect(
      names,
      containsAll(<String>[
        'basic_warnings',
        'clean_project',
        'multi_engine',
        // Nested. The old discovery listed only immediate children and
        // silently skipped this one for its entire life.
        'vhdl/basic_warnings',
      ]),
      reason:
          'discovery must recurse into subdirectories of $kProjectFixturesRoot',
    );
  });

  for (final fixture in fixtures) {
    group('project fixture: ${fixture.name}', () {
      late final CaptureManifest manifest;
      late final Map<String, EngineRecording> recordings;

      setUpAll(() {
        final captureFile = File(fixture.capturePath);
        expect(
          captureFile.existsSync(),
          isTrue,
          reason:
              'missing ${fixture.capturePath} — every fixture must record '
              'which binary produced its golden. Run '
              '`dart run tool/capture_project_fixtures.dart`.',
        );
        manifest = CaptureManifest.fromJson(
          jsonDecode(captureFile.readAsStringSync()) as Map<String, dynamic>,
        );
        recordings = <String, EngineRecording>{
          for (final id in fixture.enabledEngineIds)
            if (File(fixture.recordingPath(id)).existsSync())
              id: EngineRecording.fromJson(
                jsonDecode(File(fixture.recordingPath(id)).readAsStringSync())
                    as Map<String, dynamic>,
              ),
        };
      });

      // ── Layer 3: attribution ─────────────────────────────────────────
      test('every enabled engine is either recorded or declared unverified', () {
        for (final engineId in fixture.enabledEngineIds) {
          final hasRecording = recordings.containsKey(engineId);
          final declared = manifest.unverified[engineId];
          expect(
            hasRecording || (declared != null && declared.isNotEmpty),
            isTrue,
            reason:
                'fixture "${fixture.name}" enables engine "$engineId" but has '
                'neither engine-output/$engineId.json nor an "unverified" '
                'reason in capture.json. An expectation nobody could verify '
                'must say so out loud — that is the whole point of this '
                'corpus. Run `dart run tool/capture_project_fixtures.dart`.',
          );
          expect(
            hasRecording && declared != null,
            isFalse,
            reason:
                '"$engineId" is both recorded and declared unverified in '
                '${fixture.name}; one of the two is stale.',
          );
        }
      });

      test('recorded engines carry a binary version', () {
        for (final engineId in recordings.keys) {
          expect(
            manifest.engineVersions[engineId],
            isNotNull,
            reason:
                'capture.json records no version for "$engineId"; a golden '
                'with no attributable binary is indistinguishable from one '
                'somebody typed.',
          );
          expect(manifest.engineVersions[engineId], isNotEmpty);
        }
      });

      // ── Layer 1 + 2: argv and replay, no binary required ─────────────
      test('replaying the recordings reproduces expected.sarif.json', () async {
        final byEngine = <String, List<Violation>>{};
        for (final engineId in fixture.enabledEngineIds) {
          final recording = recordings[engineId];
          if (recording == null) continue;

          final runner = PlaybackProcessRunner(recording.invocations);
          final requests = planRequests(fixture, runner: runner);
          final request = requests[engineId];
          expect(
            request,
            isNotNull,
            reason:
                'the run planner no longer routes any source file to '
                '"$engineId" in ${fixture.name}, but a recording exists',
          );
          final engine = capturableEngine(
            engineId,
            projectRoot: fixture.dir,
            runner: runner,
          )!;
          byEngine[engineId] = await collectViolations(engine, request!);

          // Layer 1. The adapter must still ask for exactly what was
          // recorded. This is the guard that would have caught the
          // Verilator adapter passing no `-Wall`.
          expect(
            runner.requestedArguments,
            recording.invocations.map((i) => i.arguments).toList(),
            reason:
                'the $engineId adapter now builds a different argument '
                "vector than the one that produced ${fixture.name}'s "
                'golden. If the change is intentional, re-capture with '
                '`dart run tool/capture_project_fixtures.dart`.',
          );
        }

        final actual = buildProjectFixtureSarifMap(
          fixture.name,
          byEngine,
          fixtureDir: fixture.dir,
        );
        final expected =
            jsonDecode(File(fixture.expectedSarifPath).readAsStringSync())
                as Map<String, dynamic>;
        expect(
          actual,
          expected,
          reason:
              "replaying ${fixture.name}'s recorded engine output through "
              'the real adapters no longer reproduces its golden SARIF. '
              'Re-capture with '
              '`dart run tool/capture_project_fixtures.dart`.',
        );
      });

      test('the golden cites only rule ids the fixture recorded', () {
        final expected =
            jsonDecode(File(fixture.expectedSarifPath).readAsStringSync())
                as Map<String, dynamic>;
        final runs = (expected['runs'] as List).cast<Map<String, dynamic>>();
        for (final run in runs) {
          final engineId =
              ((run['tool'] as Map)['driver'] as Map)['name'] as String;
          expect(
            recordings.containsKey(engineId),
            isTrue,
            reason:
                "${fixture.name}'s golden contains a \"$engineId\" run with no "
                'engine-output/$engineId.json behind it — a result nobody '
                'captured is a result nobody verified.',
          );
        }
      });

      // ── Layer 4: the real binary, when this machine has it ───────────
      for (final engineId in fixture.enabledEngineIds) {
        final binary = kEngineBinaryNames[engineId];
        test(
          'live $engineId run still matches the golden',
          () async {
            final expected =
                jsonDecode(
                      File(fixture.expectedSarifPath).readAsStringSync(),
                    )
                    as Map<String, dynamic>;
            final goldenRun = (expected['runs'] as List)
                .cast<Map<String, dynamic>>()
                .where(
                  (r) =>
                      ((r['tool'] as Map)['driver'] as Map)['name'] == engineId,
                );
            if (goldenRun.isEmpty && !recordings.containsKey(engineId)) {
              // Declared unverified on the capture host; this machine has
              // the binary but the golden has nothing to compare against.
              // Do not invent an expectation here — re-capture instead.
              markTestSkipped(
                '$engineId is declared unverified in ${fixture.name}; '
                'this host HAS $binary, so re-capture with '
                '`dart run tool/capture_project_fixtures.dart`',
              );
              return;
            }

            const runner = SystemProcessRunner();
            final requests = planRequests(fixture, runner: runner);
            final request = requests[engineId];
            if (request == null) return;
            final engine = capturableEngine(
              engineId,
              projectRoot: fixture.dir,
              runner: runner,
            )!;
            final live = await collectViolations(engine, request);

            // Compare the finding SET, not the bytes: a different engine
            // build legitimately rewords a message. A different rule id,
            // line or severity is drift the golden must be re-cut for.
            final liveKeys = <String>{
              for (final v in live)
                '${v.ruleId}@${v.location.line}:${v.severity.name}',
            };
            final goldenKeys = <String>{
              for (final r in goldenRun) ...goldenFindingKeys(engineId, r),
            };
            final captured =
                manifest.engineVersions[engineId] ?? 'unknown build';
            expect(
              liveKeys,
              goldenKeys,
              reason:
                  'the real $engineId on this machine disagrees with the '
                  '${fixture.name} golden captured from "$captured". Either '
                  'the fixture drifted or the golden is fiction — the second '
                  'is why this test exists.',
            );
          },
          skip: binary == null
              ? '$engineId is not a PATH-resolved engine'
              : (onPath(binary) ? false : '$binary not on PATH'),
        );
      }
    });
  }
}
