// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/engine_run_status.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/parallel_engine_runner.dart';
import 'package:lintcrux/services/engines/verilator/verilator_engine.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';

import 'fake_process_runner.dart';

/// Subprocess orchestration under hostile inputs.
///
/// Every scenario drives a *real* engine ([VerilatorEngine]) through a
/// scripted [FakeProcessRunner], so the runner + watchdog + engine wiring
/// is exercised end-to-end without any real binary. A pathological engine
/// must never hang the run, leak a process, or stop the other engines.
class _FastEngine implements LintEngine {
  _FastEngine(this.id, this._violations);

  @override
  final String id;
  final List<Violation> _violations;

  @override
  String get displayName => id;

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.systemVerilog},
  );

  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async => '1.0.0';

  @override
  Stream<Violation> run(LintRunRequest request) async* {
    for (final v in _violations) {
      yield v;
    }
  }

  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) => run(request);

  @override
  void cancel() {}
}

Violation _v(String engineId) => Violation(
  engineId: engineId,
  ruleId: '$engineId/R',
  severity: Severity.warning,
  message: 'm',
  location: const SourceLocation(file: '/a/b.sv', line: 1, column: 1),
);

const _req = LintRunRequest(
  sourceFiles: ['/a/b.sv'],
  binary: EngineBinaryConfig.system(),
  language: HdlLanguage.systemVerilog,
);

void main() {
  test(
    'hung engine (no output, never exits) → timed-out, others complete',
    () async {
      final store = InMemoryViolationStore();
      // Short budget so the test runs fast; the hung engine produces no
      // output and never exits, so the watchdog must kill it.
      final runner = ParallelEngineRunner(
        store,
        engineTimeout: const Duration(milliseconds: 120),
      );
      final hungRunner = FakeProcessRunner()..holdOpen = true;
      final hung = VerilatorEngine(runner: hungRunner, projectRoot: '/w');
      final fast = _FastEngine('fast', <Violation>[_v('fast')]);

      await runner.runAll(<EngineRunPair>[
        EngineRunPair(engine: hung, request: _req),
        EngineRunPair(engine: fast, request: _req),
      ]);

      expect(runner.statusFor('verilator')?.phase, EngineRunPhase.failed);
      expect(
        runner.statusFor('verilator')?.error,
        contains('wall-clock budget'),
      );
      // The watchdog killed the hung subprocess.
      expect(hungRunner.lastProcess?.killed, isTrue);
      // The healthy engine finished regardless.
      expect(runner.statusFor('fast')?.phase, EngineRunPhase.completed);
      expect(store.byEngine['fast'], hasLength(1));

      await runner.dispose();
      await store.dispose();
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );

  test('missing binary → unavailable, other engines still run', () async {
    final store = InMemoryViolationStore();
    final runner = ParallelEngineRunner(store);
    final missingRunner = FakeProcessRunner()
      ..onStartThrows = const ProcessException('verilator', <String>[]);
    final missing = VerilatorEngine(runner: missingRunner, projectRoot: '/w');
    final fast = _FastEngine('fast', <Violation>[_v('fast')]);

    await runner.runAll(<EngineRunPair>[
      EngineRunPair(engine: missing, request: _req),
      EngineRunPair(engine: fast, request: _req),
    ]);

    expect(runner.statusFor('verilator')?.phase, EngineRunPhase.unavailable);
    expect(runner.statusFor('fast')?.phase, EngineRunPhase.completed);
    expect(store.byEngine['fast'], hasLength(1));

    await runner.dispose();
    await store.dispose();
  });

  test(
    'non-zero exit with unparseable output → completed, empty set',
    () async {
      final store = InMemoryViolationStore();
      final runner = ParallelEngineRunner(store);
      final badRunner = FakeProcessRunner()
        ..exitCode = 1
        ..stderrLines = <String>['ERROR: internal engine failure, code 99'];
      final engine = VerilatorEngine(runner: badRunner, projectRoot: '/w');

      await runner.runAll(<EngineRunPair>[
        EngineRunPair(engine: engine, request: _req),
      ]);

      // A non-zero exit with no parseable violations is a valid outcome, not
      // a crash — the engine completes with an empty violation set.
      expect(runner.statusFor('verilator')?.phase, EngineRunPhase.completed);
      expect(store.byEngine['verilator'] ?? const <Violation>[], isEmpty);

      await runner.dispose();
      await store.dispose();
    },
  );

  test(
    'both stdout and stderr are drained (no single-stream deadlock)',
    () async {
      final store = InMemoryViolationStore();
      final runner = ParallelEngineRunner(store);
      // The fake holds emission until BOTH streams are subscribed, so a
      // run that only drained one stream would hang here and trip the
      // Timeout. stdout floods while the real diagnostic is on stderr.
      final floodRunner = FakeProcessRunner()
        ..stdoutLines = List<String>.generate(5000, (i) => 'noise line $i')
        ..stderrLines = <String>[
          "%Warning-UNUSEDSIGNAL: top.sv:3:1: Signal is not used: 'q'",
        ];
      final engine = VerilatorEngine(runner: floodRunner, projectRoot: '/w');

      await runner.runAll(<EngineRunPair>[
        EngineRunPair(engine: engine, request: _req),
      ]);

      expect(runner.statusFor('verilator')?.phase, EngineRunPhase.completed);
      expect(store.byEngine['verilator'], hasLength(1));

      await runner.dispose();
      await store.dispose();
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );
}
