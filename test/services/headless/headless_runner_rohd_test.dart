// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/cli/cli_args.dart';
import 'package:lintcrux/core/cli/cli_exit_codes.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/rohd_dart_source.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/headless/headless_run_result.dart';
import 'package:lintcrux/services/headless/headless_runner.dart';
import 'package:lintcrux/services/rohd/rohd_source_loader.dart';
import 'package:path/path.dart' as p;

import '../../support/rohd_fixture_package.dart';

/// Reports one finding per line it is given.
class _Engine implements LintEngine {
  _Engine(this.file, this.lines);

  final String file;
  final List<int> lines;

  @override
  String get id => 'fake';

  @override
  String get displayName => 'fake';

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.systemVerilog},
  );

  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async => '1.0.0';

  @override
  Stream<Violation> run(LintRunRequest request) async* {
    for (final line in lines) {
      yield Violation(
        engineId: 'fake',
        ruleId: 'fake/RULE',
        severity: Severity.warning,
        message: 'finding at $line',
        location: SourceLocation(file: file, line: line, column: 1),
      );
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

void main() {
  late RohdFixturePackage pkg;
  late String projectPath;
  late String sv;

  void writeProject({Map<String, Object?>? rohdOptions}) {
    projectPath = p.join(pkg.root, 'design.lintcrux');
    File(projectPath).writeAsStringSync(
      jsonEncode(<String, Object?>{
        'version': 1,
        'name': 'design',
        'rootPath': '.',
        'sourceFiles': <String>['build/top.sv'],
        'language': 'systemverilog',
        if (rohdOptions != null)
          'perEngineOptions': <String, Object?>{kRohdOptionsKey: rohdOptions},
      }),
    );
  }

  Future<HeadlessRunResult> run() => HeadlessRunner(
    registry: EngineRegistry([
      _Engine(sv, [54, 53, 1]),
    ]),
  ).run(CliArgs(paths: <String>[projectPath]));

  setUp(() {
    pkg = RohdFixturePackage.create();
    sv = pkg.inBuild('top.sv');
    writeProject();
  });
  tearDown(() => pkg.dispose());

  test('a CI run reports the Dart source of findings on ROHD output', () async {
    final r = await run();
    expect(r.exitCode, CliExitCode.clean);
    final byLine = {for (final v in r.violations) v.location.line: v};
    final exact = RohdDartSource.fromRaw(byLine[54]!.raw)!;
    expect(exact.kind, RohdDartSourceKind.exact);
    expect(exact.primary.file, pkg.path('lib/design.dart'));
    expect(exact.primary.line, 59);
    final enclosing = RohdDartSource.fromRaw(byLine[53]!.raw)!;
    expect(enclosing.kind, RohdDartSourceKind.enclosing);
    // Nothing is known about the file header: no Dart source, still reported.
    expect(byLine[1]!.raw.containsKey(RohdDartSource.rawKey), isFalse);
    expect(r.diagnostics, isEmpty);
  });

  test('an unknown sidecar version warns and the run is unaffected', () async {
    File(pkg.inBuild('Top.flc.json')).writeAsStringSync('{"version": 99}');
    final r = await run();
    expect(r.exitCode, CliExitCode.clean);
    expect(r.violations, hasLength(3));
    expect(r.diagnostics.single, contains('version 99'));
    // The comments in the generated file still answer.
    final byLine = {for (final v in r.violations) v.location.line: v};
    expect(
      RohdDartSource.fromRaw(byLine[53]!.raw)!.fromInlineComment,
      isTrue,
    );
  });

  test('a sidecar named in the project file is found', () async {
    Directory(pkg.path('trace')).createSync();
    File(
      pkg.inBuild('Top.flc.json'),
    ).renameSync(pkg.path('trace/Top.flc.json'));
    writeProject(rohdOptions: {kRohdSidecarOption: 'trace/Top.flc.json'});
    final r = await run();
    final v54 = r.violations.firstWhere((v) => v.location.line == 54);
    expect(RohdDartSource.fromRaw(v54.raw)!.fromInlineComment, isFalse);
  });
}
