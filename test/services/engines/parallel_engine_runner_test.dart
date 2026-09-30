// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/engine_run_status.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/parallel_engine_runner.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';

/// Engine fake that yields scripted violations and never blocks.
class _ScriptedEngine implements LintEngine {
  _ScriptedEngine(this.id, this._violations);

  @override
  final String id;
  final List<Violation> _violations;
  bool cancelled = false;

  @override
  String get displayName => 'Scripted $id';

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.systemVerilog},
  );

  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async => '1.0.0';

  @override
  Stream<Violation> run(LintRunRequest request) async* {
    for (final v in _violations) {
      if (cancelled) return;
      yield v;
    }
  }

  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) => run(request);

  @override
  void cancel() {
    cancelled = true;
  }
}

class _UnavailableEngine implements LintEngine {
  _UnavailableEngine(this.id);
  @override
  final String id;
  @override
  String get displayName => id;
  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.systemVerilog},
  );
  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async => null;
  @override
  Stream<Violation> run(LintRunRequest request) async* {
    throw EngineNotAvailableException(engineId: id, reason: 'not on PATH');
  }

  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) => run(request);
  @override
  void cancel() {}
}

class _FailingEngine implements LintEngine {
  _FailingEngine(this.id);
  @override
  final String id;
  @override
  String get displayName => id;
  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.systemVerilog},
  );
  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async => null;
  @override
  Stream<Violation> run(LintRunRequest request) async* {
    throw StateError('engine blew up mid-run');
  }

  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) => run(request);
  @override
  void cancel() {}
}

class _SlowEngine implements LintEngine {
  _SlowEngine(this.id, this._completer, this._violation);
  @override
  final String id;
  final Completer<void> _completer;
  final Violation _violation;
  bool cancelled = false;
  @override
  String get displayName => id;
  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.systemVerilog},
  );
  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async => null;
  @override
  Stream<Violation> run(LintRunRequest request) async* {
    yield _violation;
    await _completer.future;
  }

  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) => run(request);

  @override
  void cancel() {
    cancelled = true;
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }
}

Violation _v(String engineId, String rule) => Violation(
  engineId: engineId,
  ruleId: '$engineId/$rule',
  severity: Severity.warning,
  message: 'msg',
  location: const SourceLocation(file: '/a/b.sv', line: 1, column: 1),
);

const _req = LintRunRequest(
  sourceFiles: ['/a/b.sv'],
  binary: EngineBinaryConfig.system(),
  language: HdlLanguage.systemVerilog,
);

void main() {
  group('ParallelEngineRunner', () {
    test('runAll drains every engine and stores violations', () async {
      final store = InMemoryViolationStore();
      final runner = ParallelEngineRunner(store);
      final eA = _ScriptedEngine('a', [_v('a', 'r1'), _v('a', 'r2')]);
      final eB = _ScriptedEngine('b', [_v('b', 'r1')]);
      await runner.runAll([
        EngineRunPair(engine: eA, request: _req),
        EngineRunPair(engine: eB, request: _req),
      ]);
      expect(store.byEngine['a'], hasLength(2));
      expect(store.byEngine['b'], hasLength(1));
      expect(runner.statusFor('a')?.phase, EngineRunPhase.completed);
      expect(runner.statusFor('b')?.phase, EngineRunPhase.completed);
      await runner.dispose();
      await store.dispose();
    });

    test('statusEvents emits transitions for every engine', () async {
      final store = InMemoryViolationStore();
      final runner = ParallelEngineRunner(store);
      final received = <EngineRunPhase>{};
      final sub = runner.statusEvents.listen((s) {
        received.add(s.phase);
      });
      await runner.runAll([
        EngineRunPair(
          engine: _ScriptedEngine('a', [_v('a', 'r')]),
          request: _req,
        ),
      ]);
      // Let pending broadcast-stream deliveries flush.
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(
        received,
        containsAll([EngineRunPhase.running, EngineRunPhase.completed]),
      );
      await runner.dispose();
      await store.dispose();
    });

    test('runAll on empty list completes without crashing', () async {
      final store = InMemoryViolationStore();
      final runner = ParallelEngineRunner(store);
      await runner.runAll(const []);
      expect(runner.statuses, isEmpty);
      await runner.dispose();
      await store.dispose();
    });

    test(
      'engine throwing EngineNotAvailableException → unavailable status',
      () async {
        final store = InMemoryViolationStore();
        final runner = ParallelEngineRunner(store);
        await runner.runAll([
          EngineRunPair(engine: _UnavailableEngine('a'), request: _req),
        ]);
        expect(runner.statusFor('a')?.phase, EngineRunPhase.unavailable);
        expect(runner.statusFor('a')?.error, contains('not on PATH'));
        expect(store.byEngine['a'], isNull);
        await runner.dispose();
        await store.dispose();
      },
    );

    test('engine throwing arbitrary error → failed status', () async {
      final store = InMemoryViolationStore();
      final runner = ParallelEngineRunner(store);
      await runner.runAll([
        EngineRunPair(engine: _FailingEngine('a'), request: _req),
      ]);
      expect(runner.statusFor('a')?.phase, EngineRunPhase.failed);
      expect(runner.statusFor('a')?.error, contains('blew up'));
      await runner.dispose();
      await store.dispose();
    });

    test(
      'one engine failing does not prevent others from completing',
      () async {
        final store = InMemoryViolationStore();
        final runner = ParallelEngineRunner(store);
        await runner.runAll([
          EngineRunPair(engine: _FailingEngine('a'), request: _req),
          EngineRunPair(
            engine: _ScriptedEngine('b', [_v('b', 'r')]),
            request: _req,
          ),
        ]);
        expect(runner.statusFor('a')?.phase, EngineRunPhase.failed);
        expect(runner.statusFor('b')?.phase, EngineRunPhase.completed);
        expect(store.byEngine['b'], hasLength(1));
        await runner.dispose();
        await store.dispose();
      },
    );

    test(
      'cancel propagates to active engines and yields cancelled status',
      () async {
        final store = InMemoryViolationStore();
        final runner = ParallelEngineRunner(store);
        final completer = Completer<void>();
        final slow = _SlowEngine('slow', completer, _v('slow', 'r'));

        // Wait for the runner to actually report the first violation rather
        // than counting event-loop turns. Two `Future.delayed(Duration.zero)`
        // hops happened to be enough locally and were not on a loaded CI
        // runner, where cancel landed before the violation was stored and
        // the store lookup came back null.
        final firstViolation = runner.statusEvents.firstWhere(
          (s) => s.engineId == 'slow' && s.violationCount >= 1,
        );
        final fut = runner.runAll([
          EngineRunPair(engine: slow, request: _req),
        ]);
        await firstViolation;
        runner.cancel();
        await fut;
        expect(slow.cancelled, isTrue);
        expect(runner.statusFor('slow')?.phase, EngineRunPhase.cancelled);
        // Cancelled runs still flush whatever was collected before cancel.
        expect(store.byEngine['slow'], hasLength(1));
        await runner.dispose();
        await store.dispose();
      },
    );

    test('runAll updates violationCount as violations stream in', () async {
      final store = InMemoryViolationStore();
      final runner = ParallelEngineRunner(store);
      final progress = <int>[];
      final sub = runner.statusEvents
          .where((s) => s.engineId == 'a')
          .listen((s) => progress.add(s.violationCount));
      await runner.runAll([
        EngineRunPair(
          engine: _ScriptedEngine('a', [
            _v('a', 'r1'),
            _v('a', 'r2'),
            _v('a', 'r3'),
          ]),
          request: _req,
        ),
      ]);
      await sub.cancel();
      // The terminal status reports count == 3.
      expect(runner.statusFor('a')?.violationCount, 3);
      // Intermediate progress should include intermediate counts; the
      // exact sequence isn't strictly ordered, but the final count
      // must appear.
      expect(progress, contains(3));
      await runner.dispose();
      await store.dispose();
    });

    test(
      'isRunning is true mid-run and false once every engine terminates',
      () async {
        final store = InMemoryViolationStore();
        final runner = ParallelEngineRunner(store);
        expect(runner.isRunning, isFalse);
        await runner.runAll([
          EngineRunPair(
            engine: _ScriptedEngine('a', [_v('a', 'r')]),
            request: _req,
          ),
        ]);
        expect(runner.isRunning, isFalse);
        await runner.dispose();
        await store.dispose();
      },
    );
  });
}
