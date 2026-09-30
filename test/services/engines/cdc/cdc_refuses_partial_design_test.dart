// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/cdc/cdc_engine.dart';

// CDC elaborates the WHOLE design — `flatten` is required for a crossing
// between two instances to be visible at all. So when the language router
// excludes sources for this engine (VHDL, today), the survivors reference
// modules that are gone, Yosys fails `hierarchy -check`, and the user is
// handed a missing-module diagnostic that names a symbol rather than the
// actual cause.
//
// A per-file linter may legitimately skip what it cannot parse. A
// whole-design analysis may not: a CDC report built from a partial netlist is
// not a smaller report, it is a WRONG one — the crossings it cannot see are
// precisely the ones spanning the excluded language.
//
// These tests pin the refusal, and the fact that it costs nothing when there
// is nothing to refuse.

/// A runner on a machine with no Yosys that records what it was asked to run.
class _SpawnRecordingProcessRunner implements ProcessRunner {
  final List<String> spawned = <String>[];

  @override
  Future<ProcessRunResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    Future<void>? cancelSignal,
    String? stdoutFilePath,
    void Function(String line)? onStderrLine,
  }) async {
    spawned.add(executable);
    throw ProcessException(executable, arguments, 'No such file or directory');
  }
}

LintRunRequest _request({
  List<String> sources = const ['a.v'],
  List<String> dropped = const <String>[],
}) => LintRunRequest(
  sourceFiles: sources,
  binary: const EngineBinaryConfig(source: EngineBinarySource.system),
  language: HdlLanguage.verilog,
  droppedSources: dropped,
);

void main() {
  group('CdcEngine refuses a partial design', () {
    test('dropped sources produce a refusal, and no elaboration', () async {
      // A runner is deliberately NOT supplied: reaching one would mean the
      // engine tried to elaborate, and the default would attempt to spawn
      // yosys. Refusing before that is the behaviour under test.
      final violations = await CdcEngine()
          .run(
            _request(sources: ['top.v'], dropped: ['pkg.vhd', 'fifo.vhd']),
          )
          .toList();

      expect(violations, hasLength(1));
      final v = violations.single;
      expect(v.ruleId, 'cdc/unsupported-sources');
      expect(v.severity, Severity.error);
      expect(
        v.ruleId,
        isNot('cdc/elaboration-failed'),
        reason:
            'The old behaviour reported this as an elaboration failure, '
            'which blamed the design for a routing decision.',
      );
      expect(v.message, contains('2 source file'));
      expect(v.message, contains('pkg.vhd'));
      expect(v.location.file, 'pkg.vhd');
    });

    test('names at most three files, then counts the rest', () async {
      final violations = await CdcEngine()
          .run(
            _request(dropped: ['a.vhd', 'b.vhd', 'c.vhd', 'd.vhd', 'e.vhd']),
          )
          .toList();

      final message = violations.single.message;
      expect(message, contains('5 source file'));
      expect(message, contains('and 2 more'));
      expect(
        message,
        isNot(contains('e.vhd')),
        reason:
            'A refusal that pastes fifty paths into one message is not a '
            'message a person reads.',
      );
    });

    test('no dropped sources means no refusal', () async {
      // Nothing was excluded, so the engine must proceed to elaboration —
      // proven here by it reaching the Yosys spawn instead of yielding the
      // refusal. The runner has no Yosys, so the run ends as unavailable.
      final runner = _SpawnRecordingProcessRunner();
      final violations = <Violation>[];
      Object? error;
      try {
        await CdcEngine(
          processRunner: runner,
        ).run(_request(sources: ['top.v'])).forEach(violations.add);
      } on EngineNotAvailableException catch (e) {
        error = e;
      }

      expect(
        violations.where((v) => v.ruleId == 'cdc/unsupported-sources'),
        isEmpty,
      );
      expect(runner.spawned, isNotEmpty);
      expect(error, isA<EngineNotAvailableException>());
    });
  });

  group('LintRunRequest carries droppedSources through copyWith', () {
    test('the incremental re-run path does not lose it', () {
      // The re-run path calls copyWith(sourceFiles: changed). If the dropped
      // set were lost there, the first run would refuse and every subsequent
      // run would analyse a partial design — the worse of the two failures,
      // because it looks like it worked.
      final original = _request(
        sources: ['a.v', 'b.v'],
        dropped: ['c.vhd'],
      );
      final rerun = original.copyWith(sourceFiles: ['a.v']);

      expect(rerun.droppedSources, ['c.vhd']);
      expect(rerun.sourceFiles, ['a.v']);
    });

    test('defaults to empty rather than null', () {
      expect(
        const LintRunRequest(
          sourceFiles: ['a.v'],
          binary: EngineBinaryConfig(source: EngineBinarySource.system),
          language: HdlLanguage.verilog,
        ).droppedSources,
        isEmpty,
      );
    });
  });
}
