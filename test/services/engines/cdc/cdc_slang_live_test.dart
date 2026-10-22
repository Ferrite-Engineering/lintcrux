// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The live assertion for the SystemVerilog package fixture
// (test/fixtures/systemverilog/cdc_packages/): the real CDC engine over a
// real Yosys, against the answer the RTL gives (see the fixture's
// PROVENANCE.md). Never against what this engine printed.
//
// Two Yosys builds matter and each test asks for its own:
//
// - With yosys-slang (the OSS CAD Suite): set OSS_CAD_SUITE to the directory
//   holding its bin/, or put a Yosys with yosys-slang on PATH. Those tests
//   are tagged `oss-cad-live`, which the CI `Test` job excludes (`-x
//   oss-cad-live`) so a runner without the suite does not count them against
//   its skip ceiling. CDC_LIVE_REQUIRED=1 turns a missing suite into a
//   failure.
// - Without it (Homebrew's, Ubuntu's): the Yosys on PATH. That test is not
//   tagged: the Linux CI leg installs Ubuntu's Yosys, which has no slang, so
//   it runs on every push there.

import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/cdc/cdc_engine.dart';
import 'package:path/path.dart' as p;

const _fixture = 'test/fixtures/systemverilog/cdc_packages';
const _files = <String>['cdc_types_pkg.sv', 'pkg_cdc_top.sv'];

bool get _required => Platform.environment['CDC_LIVE_REQUIRED'] == '1';

/// The suite's Yosys: OSS_CAD_SUITE/bin/yosys, else the `yosys` on PATH.
String? _suiteYosys() {
  final suite = Platform.environment['OSS_CAD_SUITE'];
  final exe = Platform.isWindows ? 'yosys.exe' : 'yosys';
  if (suite != null && suite.isNotEmpty) {
    final candidate = p.join(suite, 'bin', exe);
    return File(candidate).existsSync() ? candidate : null;
  }
  return _onPath(exe);
}

String? _onPath(String exe) {
  final pathVar = Platform.environment['PATH'] ?? '';
  for (final d in pathVar.split(Platform.isWindows ? ';' : ':')) {
    if (d.isEmpty) continue;
    final candidate = p.join(d, exe);
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

Future<bool> _hasSlang(String yosys) => YosysAvailabilityService(
  executableNameOverride: yosys,
).probeSlang();

LintRunRequest _request(String yosys, String root, List<String> sources) =>
    LintRunRequest(
      sourceFiles: sources,
      sourceLanguages: <String, HdlLanguage>{
        for (final s in sources) s: HdlLanguage.systemVerilog,
      },
      binary: EngineBinaryConfig(
        source: EngineBinarySource.custom,
        path: yosys,
      ),
      language: HdlLanguage.systemVerilog,
      topModule: 'pkg_cdc_top',
      projectRoot: root,
    );

/// Copies the fixture into [into] and returns the copies' paths, in
/// compilation order.
List<String> _copyFixture(String into) {
  Directory(into).createSync(recursive: true);
  return <String>[
    for (final name in _files)
      File(p.join(_fixture, name)).copySync(p.join(into, name)).path,
  ];
}

/// What the RTL says, checked against one run.
///
/// Two clock domains. `data_b <= data_a` (pkg_cdc_top.sv line 28) samples
/// the 8-bit `data_a` from clk_a in clk_b with nothing between: one
/// `cdc/unsync-multi-bit` error at line 28, `data_a` written at line 23 (the
/// clk_a `always_ff`). `req_a` reaches clk_b through `req_meta` and `req_b`
/// (lines 31 to 34): a two-flop chain, so no finding. Nothing else crosses.
void _expectTheRtlAnswer(List<Violation> violations, String top) {
  final failures = violations.where((v) => v.isAnalysisFailure).toList();
  expect(failures, isEmpty, reason: failures.map((v) => v.message).join());

  final summary = violations.singleWhere((v) => v.ruleId == 'cdc/summary');
  expect(summary.raw['domains'], 2, reason: summary.message);
  expect(summary.raw['unsafe'], 1, reason: summary.message);
  expect(summary.message, contains('clk_a'));
  expect(summary.message, contains('clk_b'));
  expect(summary.message, contains('read with yosys-slang'));

  final findings = violations
      .where(
        (v) => v.severity == Severity.error || v.severity == Severity.warning,
      )
      .toList();
  final bus = findings.single;
  expect(bus.ruleId, 'cdc/unsync-multi-bit');
  expect(bus.raw['width'], 8);
  expect(bus.raw['path'], 'data_a');
  expect(bus.message, isNot(contains('req')));
  // The project's own path, not one relative to the directory Yosys ran in.
  expect(bus.location.file, top);
  expect(bus.location.line, 28);
  expect(bus.relatedLocations.single.file, top);
  expect(bus.relatedLocations.single.line, 23);
}

void main() {
  late Directory scratch;

  setUp(() {
    YosysAvailabilityService.resetSlangProbeCacheForTesting();
    scratch = Directory.systemTemp.createTempSync('cdc_slang_live_');
  });
  tearDown(() => scratch.deleteSync(recursive: true));

  test('the fixture directory holds the design and its provenance', () {
    for (final name in <String>[..._files, 'PROVENANCE.md']) {
      expect(
        File(p.join(_fixture, name)).existsSync(),
        isTrue,
        reason: '$_fixture/$name is missing',
      );
    }
  });

  Future<String?> slangYosys() async {
    final yosys = _suiteYosys();
    if (yosys != null && await _hasSlang(yosys)) return yosys;
    const reason =
        'no Yosys with yosys-slang; set OSS_CAD_SUITE or put the OSS CAD '
        'Suite on PATH';
    if (_required) fail('CDC_LIVE_REQUIRED=1 and $reason');
    markTestSkipped(reason);
    return null;
  }

  test(
    'with yosys-slang, the package design elaborates and gives the RTL answer '
    'at the project paths (sources in the run directory)',
    () async {
      final yosys = await slangYosys();
      if (yosys == null) return;
      final root = p.join(scratch.path, 'project');
      final sources = _copyFixture(root);
      final violations = await CdcEngine()
          .run(_request(yosys, root, sources))
          .toList();
      _expectTheRtlAnswer(violations, sources.last);
    },
    tags: 'oss-cad-live',
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'with yosys-slang, a design below the run directory still reports the '
    'project paths',
    () async {
      final yosys = await slangYosys();
      if (yosys == null) return;
      // Yosys runs from the project root; the sources sit two levels down,
      // so yosys-slang writes `rtl/cdc/pkg_cdc_top.sv`.
      final root = p.join(scratch.path, 'project');
      final sources = _copyFixture(p.join(root, 'rtl', 'cdc'));
      final violations = await CdcEngine()
          .run(_request(yosys, root, sources))
          .toList();
      _expectTheRtlAnswer(violations, sources.last);
    },
    tags: 'oss-cad-live',
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'without yosys-slang, the package design is one needs-slang-frontend '
    'finding, never a parser crash',
    () async {
      final yosys = _onPath(Platform.isWindows ? 'yosys.exe' : 'yosys');
      if (yosys == null) {
        markTestSkipped('yosys not on PATH');
        return;
      }
      if (await _hasSlang(yosys)) {
        markTestSkipped('the yosys on PATH has yosys-slang');
        return;
      }
      final root = p.join(scratch.path, 'project');
      final sources = _copyFixture(root);
      final violations = await CdcEngine()
          .run(_request(yosys, root, sources))
          .toList();
      final v = violations.single;
      expect(v.ruleId, 'cdc/needs-slang-frontend');
      expect(v.isAnalysisFailure, isTrue);
      // The first package construct in compilation order: the declaration
      // on line 6 of cdc_types_pkg.sv.
      expect(v.location.file, sources.first);
      expect(v.location.line, 6);
      expect(v.message, contains('package cdc_types_pkg'));
      expect(v.message, contains('OSS CAD Suite'));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
