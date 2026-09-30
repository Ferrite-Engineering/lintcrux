// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/engine_run_status.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/parallel_engine_runner.dart';
import 'package:lintcrux/services/engines/process_runner.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';

import 'fake_process_runner.dart';

/// Cancellation propagates to *every* concurrent subprocess.
///
/// `ParallelEngineRunner.cancel()` must kill all in-flight children, not
/// just the awaited one, and must not leave the violation store half-
/// populated. Each fake engine holds a real (fake) process open and kills
/// it on `cancel`, so the test asserts on per-process `killed` flags.
class _HoldingEngine implements LintEngine {
  _HoldingEngine(this.id, this.runner);

  @override
  final String id;

  /// Each engine owns its own runner so the test can assert that *this*
  /// engine's process was the one killed.
  final FakeProcessRunner runner;

  LintProcess? _proc;

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
    final proc = await runner.start('fake-engine', const <String>[]);
    _proc = proc;
    // Drain both streams (the FakeLintProcess only emits once both are
    // subscribed) and block on the held exit code until cancel kills us.
    final outSub = proc.stdout.listen((_) {});
    final errSub = proc.stderr.listen((_) {});
    try {
      await proc.exitCode;
    } finally {
      await outSub.cancel();
      await errSub.cancel();
    }
  }

  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) => run(request);

  @override
  void cancel() => _proc?.kill();
}

const _req = LintRunRequest(
  sourceFiles: ['/a/b.sv'],
  binary: EngineBinaryConfig.system(),
  language: HdlLanguage.systemVerilog,
);

void main() {
  test('cancel kills every concurrent child, not just the first', () async {
    final store = InMemoryViolationStore();
    final runner = ParallelEngineRunner(store);
    final runners = List<FakeProcessRunner>.generate(
      6,
      (_) => FakeProcessRunner()..holdOpen = true,
    );
    final engines = <_HoldingEngine>[
      for (var i = 0; i < 6; i++) _HoldingEngine('e$i', runners[i]),
    ];

    final fut = runner.runAll(<EngineRunPair>[
      for (final e in engines) EngineRunPair(engine: e, request: _req),
    ]);

    // Let every engine start its process and subscribe to both streams.
    await Future<void>.delayed(const Duration(milliseconds: 30));

    runner.cancel();
    await fut;

    // Every one of the six fake processes received a kill.
    for (var i = 0; i < 6; i++) {
      expect(
        runners[i].lastProcess?.killed,
        isTrue,
        reason: 'engine e$i process must be killed on cancel',
      );
      expect(runner.statusFor('e$i')?.phase, EngineRunPhase.cancelled);
    }

    // The store is not left half-populated — each cancelled engine flushed
    // an empty (not partial-garbage) set.
    for (var i = 0; i < 6; i++) {
      expect(store.byEngine['e$i'] ?? const <Violation>[], isEmpty);
    }

    await runner.dispose();
    await store.dispose();
  });

  test(
    'cancel before any output still terminates and kills children',
    () async {
      final store = InMemoryViolationStore();
      final runner = ParallelEngineRunner(store);
      final procRunner = FakeProcessRunner()..holdOpen = true;
      final engine = _HoldingEngine('only', procRunner);

      final fut = runner.runAll(<EngineRunPair>[
        EngineRunPair(engine: engine, request: _req),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      runner.cancel();
      await fut;

      expect(procRunner.lastProcess?.killed, isTrue);
      expect(runner.statusFor('only')?.phase, EngineRunPhase.cancelled);

      await runner.dispose();
      await store.dispose();
    },
  );
}
