// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// VerilatorEngine's output modes against scripted processes. The SARIF text
// and the stderr transcript are one real Verilator run's two outputs
// (test/fixtures/engines/verilator/sarif/PROVENANCE.md); the expected
// findings are what the text parser reads from that run's stderr.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/process_runner.dart';
import 'package:lintcrux/services/engines/verilator/verilator_engine.dart';
import 'package:lintcrux/services/engines/verilator/verilator_parser.dart';

import '../fake_process_runner.dart';

const _dir = 'test/fixtures/sarif/verilator_capture';
const _root = '/work/sarif_design';
const _tag = 'oss-cad-2026-10-21';
const _flag = '--diagnostics-sarif-output';

/// The fixture, with `@ROOT@` (the capture directory, kept out of the
/// committed files) put back as [_root].
String _fixture(String name) =>
    File('$_dir/$name').readAsStringSync().replaceAll('@ROOT@', _root);

final List<String> _stderr = _fixture('$_tag.stderr.txt').split('\n');

List<Violation> get _expected =>
    VerilatorParser(rootPath: _root).parse(_stderr);

const _request = LintRunRequest(
  sourceFiles: <String>['$_root/sarif_design.sv'],
  binary: EngineBinaryConfig.system(),
  language: HdlLanguage.systemVerilog,
);

/// A runner whose lint invocation writes [sarif] to the path Verilator is
/// told to write it to, as the real binary does.
class _SarifRunner extends FakeProcessRunner {
  _SarifRunner({required String version, this.sarif}) {
    scripts
      ..add(FakeRunScript(stdout: <String>[version]))
      ..add(FakeRunScript(stderr: _stderr, exitCode: 1));
  }

  /// Text written to the SARIF path, or `null` to write nothing.
  String? sarif;

  /// The SARIF path the engine asked for, as last seen.
  String? sarifPath;

  /// Whether the SARIF path's directory existed when the lint ran.
  bool sarifDirExistedAtRun = false;

  @override
  Future<LintProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    final i = arguments.indexOf(_flag);
    if (i >= 0) {
      sarifPath = arguments[i + 1];
      sarifDirExistedAtRun = File(sarifPath!).parent.existsSync();
      final text = sarif;
      if (text != null) File(sarifPath!).writeAsStringSync(text);
    }
    return super.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }
}

Future<List<Violation>> _run(VerilatorEngine engine) =>
    engine.run(_request).toList();

VerilatorEngine _engine(FakeProcessRunner r) => VerilatorEngine(
  runner: r,
  projectRoot: _root,
  outputMode: VerilatorOutputMode.auto,
);

void main() {
  group('VerilatorEngine.versionWritesSarif', () {
    test('5.038 and later write SARIF', () {
      for (final v in <String>[
        'Verilator 5.038 2025-07-08 rev v5.038',
        'Verilator 5.052 2026-09-05 rev v5.052',
        'Verilator 5.053 devel rev v5.052-521-g6388139f7 (mod)',
        'Verilator 6.001 2027-01-01 rev v6.001',
      ]) {
        expect(VerilatorEngine.versionWritesSarif(v), isTrue, reason: v);
      }
    });

    test('earlier releases, and anything unreadable, do not', () {
      for (final v in <String?>[
        'Verilator 5.037 2025-06-01 rev v5.037',
        'Verilator 5.022 2024-07-01 rev v5.022',
        'Verilator 4.228 2022-10-01 rev v4.228',
        'Verilator 5.037 devel rev v5.036-12-gabc',
        '',
        'not verilator',
        null,
      ]) {
        expect(VerilatorEngine.versionWritesSarif(v), isFalse, reason: '$v');
      }
    });
  });

  group('VerilatorEngine output modes', () {
    test('the default mode spawns once and does not ask for SARIF', () async {
      final fake = FakeProcessRunner()..stderrLines = _stderr;
      final engine = VerilatorEngine(runner: fake, projectRoot: _root);
      final out = await _run(engine);
      expect(fake.invocations, hasLength(1));
      expect(fake.invocations.single.arguments, isNot(contains(_flag)));
      expect(out, equals(_expected));
    });

    test('auto on a release without SARIF reads the transcript', () async {
      final fake = _SarifRunner(
        version: 'Verilator 5.037 2025-06-01 rev v5.037',
      );
      final out = await _run(_engine(fake));
      expect(fake.invocations, hasLength(2));
      expect(fake.invocations.first.arguments, <String>['--version']);
      expect(fake.invocations.last.arguments, isNot(contains(_flag)));
      expect(out, equals(_expected));
    });

    test('auto on 5.038 or later reads the SARIF, same findings', () async {
      final fake = _SarifRunner(
        version: 'Verilator 5.053 devel rev v5.052-521-g6388139f7 (mod)',
        sarif: _fixture('$_tag.sarif'),
      );
      final out = await _run(_engine(fake));
      expect(fake.invocations.last.arguments, contains(_flag));
      expect(fake.sarifDirExistedAtRun, isTrue);
      expect(out, equals(_expected));
      // Every finding carries what the inspector reads, from the SARIF.
      for (var i = 0; i < out.length; i++) {
        expect(
          out[i].raw['verilator.continuation'],
          _expected[i].raw['verilator.continuation'],
        );
      }
      // The temporary directory the SARIF went to is gone.
      expect(File(fake.sarifPath!).parent.existsSync(), isFalse);
    });

    test('a SARIF with fixes surfaces them on the finding', () async {
      final withFixes = _fixture('$_tag.sarif').replaceFirst(
        '"ruleId": "WIDTHTRUNC",',
        '"fixes": [{"description": {"text": "fix"}}], '
            '"ruleId": "WIDTHTRUNC",',
      );
      final fake = _SarifRunner(
        version: 'Verilator 5.053 devel',
        sarif: withFixes,
      );
      final out = await _run(_engine(fake));
      expect(out.first.raw['fixes'], isNotEmpty);
      expect(out, equals(_expected));
    });

    test('invalid SARIF falls back to the transcript', () async {
      final broken = _fixture('$_tag.sarif').replaceFirst(
        '},\n            "invocations"',
        '}\n            "invocations"',
      );
      final fake = _SarifRunner(
        version: 'Verilator 5.052 2026-09-05 rev v5.052',
        sarif: broken,
      );
      final out = await _run(_engine(fake));
      expect(fake.invocations.last.arguments, contains(_flag));
      expect(out, equals(_expected));
    });

    test('no SARIF file falls back to the transcript', () async {
      final fake = _SarifRunner(version: 'Verilator 5.053 devel');
      expect(await _run(_engine(fake)), equals(_expected));
    });

    test('SARIF with no results beside findings in the transcript', () async {
      final fake = _SarifRunner(
        version: 'Verilator 5.053 devel',
        sarif: '{"runs": [{"results": []}]}',
      );
      expect(await _run(_engine(fake)), equals(_expected));
    });

    test('the version is probed once per binary', () async {
      final fake = FakeProcessRunner()
        ..scripts.addAll(<FakeRunScript>[
          const FakeRunScript(stdout: <String>['Verilator 5.037 2025-06-01']),
        ])
        ..stderrLines = _stderr;
      final engine = _engine(fake);
      await _run(engine);
      await _run(engine);
      final probes = fake.invocations.where(
        (i) => i.arguments.length == 1 && i.arguments.single == '--version',
      );
      expect(probes, hasLength(1));
      expect(fake.invocations, hasLength(3));
    });

    test('a failed run still fails when SARIF has no located result', () async {
      final fake = FakeProcessRunner()
        ..scripts.addAll(<FakeRunScript>[
          const FakeRunScript(stdout: <String>['Verilator 5.053 devel']),
          const FakeRunScript(
            stderr: <String>[
              '%Error: Cannot find file containing module: "top"',
            ],
            exitCode: 1,
          ),
        ]);
      expect(
        () => _run(_engine(fake)),
        throwsA(isA<EngineRunFailedException>()),
      );
    });
  });
}
