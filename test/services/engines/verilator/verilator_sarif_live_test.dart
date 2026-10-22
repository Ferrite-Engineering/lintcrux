// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The Verilator engine over a real Verilator, once reading stderr and once
// reading SARIF, against the answer the RTL gives (see the fixture's
// PROVENANCE.md). Never against what either channel printed.
//
// Tagged `oss-cad-live`, which the CI `Test` job excludes (`-x oss-cad-live`).
// Set OSS_CAD_SUITE to a suite directory holding bin/verilator (the OSS CAD
// Suite's Verilator is 5.051 or later). CDC_LIVE_REQUIRED=1 turns a missing
// suite into a failure.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/process_runner.dart';
import 'package:lintcrux/services/engines/verilator/verilator_engine.dart';
import 'package:path/path.dart' as p;

const _fixture = 'test/fixtures/sarif/verilator_capture';
const _design = 'sarif_design.sv';

bool get _required => Platform.environment['CDC_LIVE_REQUIRED'] == '1';

String? _suiteVerilator() {
  final suite = Platform.environment['OSS_CAD_SUITE'];
  if (suite == null || suite.isEmpty) return null;
  final exe = p.join(
    suite,
    'bin',
    Platform.isWindows ? 'verilator.exe' : 'verilator',
  );
  return File(exe).existsSync() ? exe : null;
}

/// Records every argv the engine hands to the real runner.
class _RecordingRunner implements ProcessRunner {
  final List<List<String>> argvs = <List<String>>[];

  @override
  Future<LintProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    argvs.add(arguments);
    return const SystemProcessRunner().start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }
}

void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('vl_sarif_live_'));
  tearDown(() => scratch.deleteSync(recursive: true));

  test(
    'the SARIF channel reports the RTL answer, the same findings as stderr',
    () async {
      final verilator = _suiteVerilator();
      if (verilator == null) {
        const reason = 'no OSS CAD Suite Verilator; set OSS_CAD_SUITE';
        if (_required) fail('CDC_LIVE_REQUIRED=1 and $reason');
        markTestSkipped(reason);
        return;
      }
      final root = scratch.path;
      final source = p.join(root, _design);
      File(p.join(_fixture, _design)).copySync(source);
      final request = LintRunRequest(
        sourceFiles: <String>[source],
        binary: EngineBinaryConfig(
          source: EngineBinarySource.custom,
          path: verilator,
        ),
        language: HdlLanguage.systemVerilog,
      );

      final text = await VerilatorEngine(
        projectRoot: root,
      ).run(request).toList();
      final recorder = _RecordingRunner();
      final sarif = await VerilatorEngine(
        runner: recorder,
        projectRoot: root,
        outputMode: VerilatorOutputMode.auto,
      ).run(request).toList();

      // The SARIF channel was really used.
      expect(
        recorder.argvs.last,
        contains('--diagnostics-sarif-output'),
        reason: 'a Verilator of 5.038 or later is asked for SARIF',
      );

      // The answer from the RTL (the header comment of sarif_design.sv):
      // one WIDTHTRUNC on line 21, UNUSEDSIGNAL for `unread_sig` (line 18)
      // and for the upper bits of `a` (the declaration, line 13), UNDRIVEN
      // for `undriven_sig` (line 19), and MULTIDRIVEN twice for `md`.
      Map<String, int> byRule(List<Violation> vs) {
        final out = <String, int>{};
        for (final v in vs) {
          out[v.ruleId] = (out[v.ruleId] ?? 0) + 1;
        }
        return out;
      }

      const answer = <String, int>{
        'verilator/WIDTHTRUNC': 1,
        'verilator/UNUSEDSIGNAL': 2,
        'verilator/UNDRIVEN': 1,
        'verilator/MULTIDRIVEN': 2,
      };
      expect(byRule(sarif), answer);
      expect(
        sarif
            .where((v) => v.ruleId == 'verilator/WIDTHTRUNC')
            .single
            .location
            .line,
        21,
      );
      expect(
        sarif.every((v) => v.location.file == source),
        isTrue,
        reason:
            'paths come back in the spelling of the project root, '
            'also under a symlinked temp directory',
      );

      // And the channel changes nothing about a finding.
      expect(sarif, equals(text));
      for (var i = 0; i < text.length; i++) {
        expect(
          sarif[i].raw['verilator.continuation'],
          text[i].raw['verilator.continuation'],
        );
      }
    },
    tags: 'oss-cad-live',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
