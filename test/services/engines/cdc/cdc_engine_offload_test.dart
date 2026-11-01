// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crux_netlist/crux_netlist.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/cdc/cdc_domain_analysis.dart';
import 'package:lintcrux/services/engines/cdc/cdc_engine.dart';
import 'package:lintcrux/services/engines/cdc/cdc_netlist_reader.dart';
import 'package:path/path.dart' as p;

// The netlist read and the domain analysis run off the UI isolate.
//
// On a flattened SoC (OpenTitan Earl Grey: 739,000 cells) the two take tens
// of seconds. Run on the UI isolate they stop frames, tooltips and the Cancel
// button for that long: the Run button's ring freezes and the window goes
// unresponsive until the table fills. These tests give the analysis a slow
// stretch and watch a timer on the calling isolate across it.

/// A Yosys stand-in that answers the probes and writes [json] where the
/// script asks for it.
class _FakeYosys implements ProcessRunner {
  _FakeYosys(this.json, {this.elaborationTime = Duration.zero});

  final String json;

  /// How long the elaboration takes before the netlist appears.
  final Duration elaborationTime;

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
    if (arguments.length == 1 && arguments.single == '-V') {
      return const ProcessRunResult(
        exitCode: 0,
        stdout: 'Yosys 0.70',
        stderr: '',
      );
    }
    final out = RegExp('write_json "([^"]+)"').firstMatch(arguments.last);
    if (out == null) {
      return const ProcessRunResult(exitCode: 1, stdout: '', stderr: 'no out');
    }
    await Future<void>.delayed(elaborationTime);
    File(out.group(1)!).writeAsStringSync(json);
    return const ProcessRunResult(exitCode: 0, stdout: '', stderr: '');
  }
}

/// One flop in clk_a driving one in clk_b directly: a single unsafe crossing.
String _crossingJson() {
  Map<String, Object?> dff(int clk, int d, int q) => <String, Object?>{
    'hide_name': 0,
    'type': r'$dff',
    'parameters': <String, Object?>{'WIDTH': 1, 'CLK_POLARITY': 1},
    'attributes': <String, Object?>{},
    'port_directions': <String, Object?>{
      'CLK': 'input',
      'D': 'input',
      'Q': 'output',
    },
    'connections': <String, Object?>{
      'CLK': <Object>[clk],
      'D': <Object>[d],
      'Q': <Object>[q],
    },
  };
  Map<String, Object?> net(List<Object> bits) => <String, Object?>{
    'hide_name': 0,
    'bits': bits,
    'attributes': <String, Object?>{},
  };
  Map<String, Object?> port(String dir, int bit) => <String, Object?>{
    'direction': dir,
    'bits': <Object>[bit],
  };
  return jsonEncode(<String, Object?>{
    'creator': 'hand-written',
    'modules': <String, Object?>{
      'top': <String, Object?>{
        'attributes': <String, Object?>{'top': 1},
        'ports': <String, Object?>{
          'clk_a': port('input', 2),
          'clk_b': port('input', 3),
          'd': port('input', 4),
          'q': port('output', 6),
        },
        'cells': <String, Object?>{
          'flag_a': dff(2, 4, 5),
          'flag_b': dff(3, 5, 6),
        },
        'netnames': <String, Object?>{
          'clk_a': net(<Object>[2]),
          'clk_b': net(<Object>[3]),
          'd': net(<Object>[4]),
          'flag_a': net(<Object>[5]),
          'q': net(<Object>[6]),
        },
      },
    },
  });
}

/// The real analysis, after spinning for [millis] and noting which isolate
/// it ran on. Stands in for the minutes-long analysis of a full SoC.
class _SlowAnalysis extends CdcDomainAnalysis {
  const _SlowAnalysis(this.millis);

  final int millis;

  @override
  CdcAnalysisResult analyze(NetlistModel netlist, {String? topModuleName}) {
    final clock = Stopwatch()..start();
    while (clock.elapsedMilliseconds < millis) {}
    final real = super.analyze(netlist, topModuleName: topModuleName);
    return CdcAnalysisResult(
      domains: real.domains,
      crossings: real.crossings,
      diagnostics: <String>[
        ...real.diagnostics,
        'ran on ${Isolate.current.debugName}',
      ],
    );
  }
}

/// The shape the Pro overlay hands the engine: a built-in analysis carrying
/// a lookup closure that captures plain data, built where nothing else is in
/// scope.
CdcDomainAnalysis _analysisWithWaiver(Map<String, String> reasons) =>
    CdcDomainAnalysis(
      reviewedCrossing: ({required sourceClock, required destClock, netName}) =>
          reasons[netName],
    );

void main() {
  late Directory temp;
  late String source;

  setUp(() {
    YosysAvailabilityService.resetSlangProbeCacheForTesting();
    temp = Directory.systemTemp.createTempSync('cdc-offload-');
    source = p.join(temp.path, 'top.v');
    File(source).writeAsStringSync('module top(input clk_a); endmodule\n');
  });

  tearDown(() {
    YosysAvailabilityService.resetSlangProbeCacheForTesting();
    temp.deleteSync(recursive: true);
  });

  LintRunRequest request() => LintRunRequest(
    sourceFiles: <String>[source],
    binary: const EngineBinaryConfig.system(),
    language: HdlLanguage.verilog,
    topModule: 'top',
    projectRoot: temp.path,
  );

  CdcEngine engine(
    CdcDomainAnalysis analysis, {
    String? json,
    Duration elaborationTime = Duration.zero,
  }) => CdcEngine(
    processRunner: _FakeYosys(
      json ?? _crossingJson(),
      elaborationTime: elaborationTime,
    ),
    tempDirectory: temp,
    analysis: analysis,
  );

  List<String> ruleIds(List<Violation> vs) => <String>[
    for (final v in vs) v.ruleId,
  ];

  test(
    'the calling isolate keeps running while the analysis is busy',
    () async {
      // A timer on this isolate is the stand-in for frames, tooltips and
      // the ring: if something blocks the isolate, it stops firing.
      var last = DateTime.now();
      var longestGap = Duration.zero;
      final ticker = Timer.periodic(const Duration(milliseconds: 10), (_) {
        final now = DateTime.now();
        final gap = now.difference(last);
        if (gap > longestGap) longestGap = gap;
        last = now;
      });
      addTearDown(ticker.cancel);

      final violations = await engine(
        const _SlowAnalysis(1500),
      ).run(request()).toList();
      final finalGap = DateTime.now().difference(last);
      if (finalGap > longestGap) longestGap = finalGap;

      expect(
        longestGap,
        lessThan(const Duration(milliseconds: 500)),
        reason:
            'the isolate stood still for $longestGap while the analysis ran '
            'for 1.5 s',
      );
      expect(
        violations.singleWhere((v) => v.ruleId == 'cdc/analysis-note').message,
        'ran on lintcrux-cdc-analysis',
      );
    },
  );

  test('the findings are those of the analysis run in place', () async {
    final json = _crossingJson();
    final inPlace = const CdcDomainAnalysis().analyze(
      const CdcNetlistReader().readString(json, topModule: 'top'),
      topModuleName: 'top',
    );

    final violations = await engine(
      const CdcDomainAnalysis(),
      json: json,
    ).run(request()).toList();

    expect(ruleIds(violations), <String>[
      'cdc/unsync-single-bit',
      'cdc/summary',
    ]);
    final summary = violations.singleWhere((v) => v.ruleId == 'cdc/summary');
    expect(summary.raw['domains'], inPlace.domains.length);
    expect(summary.raw['crossings'], inPlace.crossings.length);
    expect(summary.raw['unsafe'], 1);
  });

  test(
    'a lookup closure on the analysis, as Pro supplies, still applies',
    () async {
      final violations = await engine(
        _analysisWithWaiver(<String, String>{'flag_a': 'accepted at boot'}),
      ).run(request()).toList();

      final note = violations.singleWhere(
        (v) => v.ruleId == 'cdc/reviewed-crossing',
      );
      expect(note.message, contains('accepted at boot'));
      expect(
        violations.where((v) => v.ruleId == 'cdc/unsync-single-bit'),
        isEmpty,
      );
    },
  );

  test('an analysis that cannot be sent to an isolate still runs', () async {
    final port = RawReceivePort();
    addTearDown(port.close);
    final unsendable = CdcDomainAnalysis(
      reviewedCrossing: ({required sourceClock, required destClock, netName}) =>
          port.hashCode == 0 ? 'never' : null,
    );

    final violations = await engine(unsendable).run(request()).toList();

    expect(ruleIds(violations), <String>[
      'cdc/unsync-single-bit',
      'cdc/summary',
    ]);
  });

  test('an unreadable netlist is still reported as such', () async {
    final violations = await engine(
      const CdcDomainAnalysis(),
      json: '{"modules": ',
    ).run(request()).toList();

    final v = violations.single;
    expect(v.ruleId, 'cdc/elaboration-failed');
    expect(v.message, contains('could not read the elaborated netlist'));
    expect(v.isAnalysisFailure, isTrue);
  });

  test('cancel stops a long analysis promptly and ends the run', () async {
    final cdc = engine(const _SlowAnalysis(30000));
    final clock = Stopwatch()..start();
    final done = cdc.run(request()).toList();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    cdc.cancel();
    final violations = await done.timeout(const Duration(seconds: 5));

    expect(violations, isEmpty);
    expect(clock.elapsed, lessThan(const Duration(seconds: 5)));
    expect(
      temp.listSync().whereType<File>().map((f) => p.basename(f.path)),
      <String>['top.v'],
      reason: 'the run owns its netlist file and removes it when cancelled',
    );
  });

  test('a cancel that lands while Yosys runs skips the read', () async {
    final cdc = engine(
      const _SlowAnalysis(30000),
      elaborationTime: const Duration(milliseconds: 500),
    );
    final done = cdc.run(request()).toList();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    cdc.cancel();
    final violations = await done.timeout(const Duration(seconds: 5));
    expect(violations, isEmpty);
  });
}
