// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/services/engines/cdc/cdc_domain_analysis.dart';
import 'package:lintcrux/services/engines/cdc/cdc_engine.dart';
import 'package:lintcrux/services/engines/cdc/cdc_netlist_reader.dart';
import 'package:path/path.dart' as p;

// How the CDC summary names clock domains that are the bits of one net.
//
// A clock manager that drives a packed struct of clocks gives the netlist one
// net name for all of them, so each domain's `clockName` is that one name.
// The summary used to print it once per bit, which reads like a bug.

/// A module with a [busWidth]-bit clock net `clks` and a single-bit clock
/// `clk_b`; one flop on each clock bit, nothing crossing.
String _clockBusJson(int busWidth) {
  Map<String, Object?> dff(int clk, int d, int q) => <String, Object?>{
    'hide_name': 0,
    'type': r'$dff',
    'parameters': <String, Object?>{'WIDTH': 1, 'CLK_POLARITY': 1},
    'attributes': <String, Object?>{},
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
  // Bits 2.. are the bus, then clk_b, then one data bit per flop.
  final busBits = <int>[for (var i = 0; i < busWidth; i++) 2 + i];
  final clkB = 2 + busWidth;
  final firstData = clkB + 1;
  final cells = <String, Object?>{
    for (var i = 0; i < busWidth; i++)
      'flop_$i': dff(busBits[i], firstData + i, firstData + i + 100),
    'flop_b': dff(clkB, firstData, firstData + 200),
  };
  return jsonEncode(<String, Object?>{
    'creator': 'hand-written',
    'modules': <String, Object?>{
      'top': <String, Object?>{
        'attributes': <String, Object?>{'top': 1},
        'ports': <String, Object?>{
          'clks': <String, Object?>{'direction': 'input', 'bits': busBits},
          'clk_b': <String, Object?>{
            'direction': 'input',
            'bits': <Object>[clkB],
          },
        },
        'cells': cells,
        'netnames': <String, Object?>{
          'clks': net(<Object>[...busBits]),
          'clk_b': net(<Object>[clkB]),
        },
      },
    },
  });
}

class _FakeYosys implements ProcessRunner {
  _FakeYosys(this.json);

  final String json;

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
    final out = RegExp('write_json "([^"]+)"').firstMatch(arguments.last);
    if (out == null) {
      return const ProcessRunResult(
        exitCode: 0,
        stdout: 'Yosys 0.70',
        stderr: '',
      );
    }
    File(out.group(1)!).writeAsStringSync(json);
    return const ProcessRunResult(exitCode: 0, stdout: '', stderr: '');
  }
}

CdcAnalysisResult _analyse(int busWidth) => const CdcDomainAnalysis().analyze(
  const CdcNetlistReader().readString(_clockBusJson(busWidth)),
);

CdcClockDomain _domain(String name, [int? bit]) => CdcClockDomain(
  domainKey: '$name$bit',
  clockName: name,
  registerPaths: const <String>[],
  bitIndex: bit,
);

void main() {
  group('the domains of a clock bus', () {
    test('share the net name and differ by bit', () {
      final domains = _analyse(5).domains;
      expect(domains, hasLength(6));
      final bus = domains.where((d) => d.clockName == 'clks').toList();
      expect(bus.map((d) => d.bitIndex), <int>[0, 1, 2, 3, 4]);
      expect(
        domains.singleWhere((d) => d.clockName == 'clk_b').bitIndex,
        isNull,
        reason: 'a clock on a net of its own has no bit to name',
      );
    });
  });

  group('cdcDomainListLabel', () {
    test('groups many bits of one net into a count', () {
      expect(
        cdcDomainListLabel(_analyse(30).domains),
        'clk_b, clks: 30 bits',
      );
    });

    test('names each bit when a few share a net', () {
      expect(
        cdcDomainListLabel(_analyse(3).domains),
        'clk_b, clks[0], clks[1], clks[2]',
      );
    });

    test('a name that appears once is printed as it always was', () {
      expect(
        cdcDomainListLabel(<CdcClockDomain>[
          _domain('clk_a'),
          _domain('clk_b'),
        ]),
        'clk_a, clk_b',
      );
      expect(
        cdcDomainListLabel(<CdcClockDomain>[_domain('clks', 2)]),
        'clks',
      );
    });

    test('repeats of a name with no bit are counted, not guessed at', () {
      final generated = <CdcClockDomain>[
        for (var i = 0; i < 5; i++) _domain(r'$and$rtl/gate.v:24$1_Y'),
      ];
      expect(
        cdcDomainListLabel(generated),
        'generated clock (gate.v:24): 5 domains',
      );
    });
  });

  test('the summary sentence keeps its shape with a grouped list', () async {
    final temp = Directory.systemTemp.createTempSync('cdc-label-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final source = p.join(temp.path, 'top.v');
    File(source).writeAsStringSync('module top; endmodule\n');
    final violations =
        await CdcEngine(
              processRunner: _FakeYosys(_clockBusJson(30)),
              tempDirectory: temp,
            )
            .run(
              LintRunRequest(
                sourceFiles: <String>[source],
                binary: const EngineBinaryConfig.system(),
                language: HdlLanguage.verilog,
                topModule: 'top',
                projectRoot: temp.path,
              ),
            )
            .toList();

    final summary = violations.singleWhere((v) => v.ruleId == 'cdc/summary');
    expect(
      summary.message,
      'CDC analysed 31 clock domain(s) (clk_b, clks: 30 bits) and found '
      '0 crossing(s), 0 unsafe.',
    );
    expect(summary.raw['domains'], 31);
  });
}
