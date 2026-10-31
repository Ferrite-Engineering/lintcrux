// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/cli/cli_args_parser.dart';
import 'package:lintcrux/domain/enums/elaboration_time_limit.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/engine_watchdog.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/engine_run_status.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/cdc/cdc_engine.dart';
import 'package:lintcrux/services/engines/constraints/constraints_engine.dart';
import 'package:lintcrux/services/engines/default_engine_registry.dart';
import 'package:lintcrux/services/engines/parallel_engine_runner.dart';
import 'package:lintcrux/services/engines/yosys/yosys_check_engine.dart';
import 'package:lintcrux/services/engines/yosys/yosys_engine_budget.dart';
import 'package:lintcrux/services/headless/headless_runner.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';
import 'package:path/path.dart' as p;

const int _mb = 1024 * 1024;
const Duration _engineTimeout = Duration(seconds: 90);

/// An engine that reports nothing, with or without the Yosys capability.
class _QuietEngine implements LintEngine {
  _QuietEngine(this.id, {required this.yosys});

  @override
  final String id;
  final bool yosys;

  @override
  String get displayName => id;

  @override
  EngineCapabilities get capabilities => EngineCapabilities(
    supportedLanguages: const {HdlLanguage.systemVerilog},
    cacheable: false,
    elaboratesWithYosys: yosys,
  );

  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async => '1';

  @override
  Stream<Violation> run(LintRunRequest request) =>
      const Stream<Violation>.empty();

  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) => run(request);

  @override
  void cancel() {}
}

/// Records the budget the runner asks it to enforce, per engine.
class _RecordingWatchdog implements EngineWatchdog {
  final Map<String, Duration> budgets = <String, Duration>{};

  @override
  Stream<T> guard<T>(
    Stream<T> source, {
    required Duration timeout,
    required String engineId,
    required void Function() onTimeout,
  }) {
    budgets[engineId] = timeout;
    return source;
  }
}

EngineRunPair _pair(LintEngine engine, List<String> sources) => EngineRunPair(
  engine: engine,
  request: LintRunRequest(
    sourceFiles: sources,
    binary: const EngineBinaryConfig.system(),
    language: HdlLanguage.systemVerilog,
  ),
);

/// A sparse file of [bytes]: its length is all the budget reads.
String _sourceOf(Directory dir, String name, int bytes) {
  final path = p.join(dir.path, name);
  File(path).openSync(mode: FileMode.write)
    ..truncateSync(bytes)
    ..closeSync();
  return path;
}

void main() {
  group('YosysEngineBudget', () {
    test('a small source gets the floor', () {
      expect(YosysEngineBudget.forSourceBytes(0), YosysEngineBudget.floor);
      expect(
        YosysEngineBudget.forSourceBytes(4 * 1024),
        YosysEngineBudget.floor,
      );
    });

    test('the engine timeout raises the floor, so no run gets less time', () {
      expect(
        YosysEngineBudget.forSourceBytes(0, minimum: _engineTimeout),
        _engineTimeout,
      );
      // 16 MB is 64 s at 256 KB/s: under the 90 s engine timeout.
      expect(
        YosysEngineBudget.forSourceBytes(16 * _mb, minimum: _engineTimeout),
        _engineTimeout,
      );
    });

    test('scales linearly with source size between floor and ceiling', () {
      // 64 MB at 256 KB/s = 256 s.
      final budget = YosysEngineBudget.forSourceBytes(64 * _mb)!;
      expect(budget, const Duration(seconds: 256));
      expect(
        YosysEngineBudget.forSourceBytes(128 * _mb),
        budget * 2,
        reason: 'twice the source, twice the budget',
      );
      expect(
        YosysEngineBudget.forSourceBytes(64 * _mb, minimum: _engineTimeout),
        budget,
        reason: 'past the engine timeout the size decides',
      );
    });

    test(
      'gives a five-million-gate source several times what Yosys needed',
      () {
        // The 660 MB structural netlist of five million gates took Yosys 403 s
        // on a fast desktop. A machine several times slower must still finish.
        final budget = YosysEngineBudget.forSourceBytes(660 * _mb)!;
        expect(budget, greaterThan(const Duration(seconds: 403 * 6)));
        expect(budget, const Duration(minutes: 44));
      },
    );

    test('a source beyond the ceiling gets the ceiling', () {
      expect(
        YosysEngineBudget.forSourceBytes(50 * 1024 * _mb),
        YosysEngineBudget.ceiling,
      );
    });

    test('extended allows four times the automatic budget', () {
      for (final bytes in <int>[0, 64 * _mb, 50 * 1024 * _mb]) {
        expect(
          YosysEngineBudget.forSourceBytes(
            bytes,
            limit: ElaborationTimeLimit.extended,
            minimum: _engineTimeout,
          ),
          YosysEngineBudget.forSourceBytes(bytes, minimum: _engineTimeout)! * 4,
          reason: '$bytes bytes',
        );
      }
    });

    test('none gives no timer', () {
      expect(
        YosysEngineBudget.forSourceBytes(
          64 * _mb,
          limit: ElaborationTimeLimit.none,
        ),
        isNull,
      );
    });

    test('never returns a zero or negative budget', () {
      for (final limit in <ElaborationTimeLimit>[
        ElaborationTimeLimit.automatic,
        ElaborationTimeLimit.extended,
      ]) {
        expect(
          YosysEngineBudget.forSourceBytes(0, limit: limit),
          greaterThan(Duration.zero),
          reason: limit.name,
        );
      }
    });

    test('sourceBytesOf sums the files and counts a missing one as empty', () {
      final dir = Directory.systemTemp.createTempSync('lintcrux_budget_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final a = _sourceOf(dir, 'a.sv', 1000);
      final b = _sourceOf(dir, 'b.sv', 2345);
      return expectLater(
        YosysEngineBudget.sourceBytesOf(<String>[
          a,
          b,
          p.join(dir.path, 'missing.sv'),
        ]),
        completion(3345),
      );
    });
  });

  group('the engines that elaborate with Yosys say so', () {
    test('yosys, cdc and constraints, and no other registered engine', () {
      final registry = defaultEngineRegistry();
      final yosysBacked = <String>{
        for (final e in registry.engines)
          if (e.capabilities.elaboratesWithYosys) e.id,
      };
      expect(yosysBacked, <String>{'yosys', 'cdc', 'constraints'});
      expect(YosysCheckEngine().capabilities.elaboratesWithYosys, isTrue);
      expect(CdcEngine().capabilities.elaboratesWithYosys, isTrue);
      expect(ConstraintsEngine().capabilities.elaboratesWithYosys, isTrue);
    });
  });

  group('headless', () {
    final parser = CliArgsParser();

    test('without --engine-timeout the Yosys-backed engines scale', () {
      final args = parser.parse(const ['a.sv']).args!;
      expect(
        HeadlessRunner.yosysTimeLimitFor(args),
        ElaborationTimeLimit.automatic,
      );
    });

    test('an explicit --engine-timeout applies to every engine', () {
      final args = parser.parse(const [
        '--engine-timeout',
        '900',
        'a.sv',
      ]).args!;
      expect(HeadlessRunner.yosysTimeLimitFor(args), isNull);
    });

    test('the runner defaults to the scaled budget', () {
      expect(
        HeadlessRunner(registry: defaultEngineRegistry()).yosysTimeLimit,
        ElaborationTimeLimit.automatic,
      );
    });
  });

  group('ParallelEngineRunner budgets', () {
    late Directory dir;
    late String big;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('lintcrux_budget_runner_');
      // 160 MB is 640 s at 256 KB/s.
      big = _sourceOf(dir, 'soc.sv', 160 * _mb);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    ParallelEngineRunner runner(
      _RecordingWatchdog watchdog, {
      ElaborationTimeLimit? limit = ElaborationTimeLimit.automatic,
    }) => ParallelEngineRunner(
      InMemoryViolationStore(),
      watchdog: watchdog,
      engineTimeout: _engineTimeout,
      yosysTimeLimit: limit,
    );

    test('a Yosys-backed engine gets the scaled budget, the others keep the '
        'engine timeout', () async {
      final watchdog = _RecordingWatchdog();
      final r = runner(watchdog);
      addTearDown(r.dispose);
      await r.runAll(<EngineRunPair>[
        _pair(_QuietEngine('cdc', yosys: true), <String>[big]),
        _pair(_QuietEngine('verilator', yosys: false), <String>[big]),
      ]);
      expect(watchdog.budgets['cdc'], const Duration(seconds: 640));
      expect(watchdog.budgets['verilator'], _engineTimeout);
      expect(r.statusFor('cdc')!.phase, EngineRunPhase.completed);
    });

    test(
      'a small design is never given less than the engine timeout',
      () async {
        final watchdog = _RecordingWatchdog();
        final r = runner(watchdog);
        addTearDown(r.dispose);
        await r.runAll(<EngineRunPair>[
          _pair(_QuietEngine('yosys', yosys: true), <String>[
            _sourceOf(dir, 'tiny.sv', 4096),
          ]),
        ]);
        expect(watchdog.budgets['yosys'], _engineTimeout);
      },
    );

    test('Extended allows four times as long', () async {
      final watchdog = _RecordingWatchdog();
      final r = runner(watchdog, limit: ElaborationTimeLimit.extended);
      addTearDown(r.dispose);
      await r.runAll(<EngineRunPair>[
        _pair(_QuietEngine('cdc', yosys: true), <String>[big]),
        _pair(_QuietEngine('verible', yosys: false), <String>[big]),
      ]);
      expect(watchdog.budgets['cdc'], const Duration(seconds: 640 * 4));
      expect(watchdog.budgets['verible'], _engineTimeout);
    });

    test('No limit runs a Yosys-backed engine with no timer', () async {
      final watchdog = _RecordingWatchdog();
      final r = runner(watchdog, limit: ElaborationTimeLimit.none);
      addTearDown(r.dispose);
      await r.runAll(<EngineRunPair>[
        _pair(_QuietEngine('constraints', yosys: true), <String>[big]),
        _pair(_QuietEngine('slang', yosys: false), <String>[big]),
      ]);
      expect(watchdog.budgets.containsKey('constraints'), isFalse);
      expect(watchdog.budgets['slang'], _engineTimeout);
      expect(r.statusFor('constraints')!.phase, EngineRunPhase.completed);
    });

    test('no limit set (an explicit --engine-timeout) gives every engine the '
        'engine timeout', () async {
      final watchdog = _RecordingWatchdog();
      final r = runner(watchdog, limit: null);
      addTearDown(r.dispose);
      await r.runAll(<EngineRunPair>[
        _pair(_QuietEngine('cdc', yosys: true), <String>[big]),
      ]);
      expect(watchdog.budgets['cdc'], _engineTimeout);
    });
  });
}
