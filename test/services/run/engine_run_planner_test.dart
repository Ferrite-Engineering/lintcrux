// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/project_source_file.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/run/engine_run_planner.dart';

class _Engine implements LintEngine {
  _Engine(this.id, this.languages);

  @override
  final String id;
  final Set<HdlLanguage> languages;

  @override
  String get displayName => id;
  @override
  EngineCapabilities get capabilities =>
      EngineCapabilities(supportedLanguages: languages);
  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async => '1';
  @override
  Stream<Violation> run(LintRunRequest request) => const Stream.empty();
  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changed,
  ) => const Stream.empty();
  @override
  void cancel() {}
}

void main() {
  const planner = EngineRunPlanner();

  final registry = EngineRegistry(<LintEngine>[
    _Engine('verilator', const {
      HdlLanguage.verilog,
      HdlLanguage.systemVerilog,
    }),
    _Engine('ghdl', const {HdlLanguage.vhdl}),
    _Engine('slang', const {HdlLanguage.systemVerilog}),
  ]);

  const bundled = EngineBinaryConfig.system();
  EngineBinaryConfig binaryFor(String _) => bundled;

  const project = LintProject(
    name: 'design',
    rootPath: '/repo',
    sourceFiles: <String>['/repo/top.sv', '/repo/pkg.vhd'],
    language: HdlLanguage.mixed,
  );

  test('routes each source file only to engines that accept it', () {
    final plan = planner.plan(
      project: project,
      registry: registry,
      binaryConfigFor: binaryFor,
    );
    final byId = <String, List<String>>{
      for (final pair in plan.pairs) pair.engine.id: pair.request.sourceFiles,
    };
    expect(byId['verilator'], <String>['/repo/top.sv']);
    expect(byId['ghdl'], <String>['/repo/pkg.vhd']);
    expect(byId['slang'], <String>['/repo/top.sv']);
  });

  test('every request carries the project root', () {
    final plan = planner.plan(
      project: project,
      registry: registry,
      binaryConfigFor: binaryFor,
    );
    expect(plan.pairs, isNotEmpty);
    for (final pair in plan.pairs) {
      expect(pair.request.projectRoot, '/repo', reason: pair.engine.id);
    }
  });

  test('the CDC engine is handed the Yosys binary configuration', () {
    final yosysBacked = EngineRegistry(<LintEngine>[
      _Engine('yosys', const {HdlLanguage.systemVerilog}),
      _Engine('cdc', const {HdlLanguage.systemVerilog}),
    ]);
    final asked = <String>[];
    final plan = planner.plan(
      project: project,
      registry: yosysBacked,
      binaryConfigFor: (id) {
        asked.add(id);
        return id == 'yosys'
            ? const EngineBinaryConfig(
                source: EngineBinarySource.custom,
                path: '/opt/y/bin/yosys',
              )
            : bundled;
      },
    );
    expect(asked, <String>['yosys', 'yosys']);
    for (final pair in plan.pairs) {
      expect(
        pair.request.binary.path,
        '/opt/y/bin/yosys',
        reason: pair.engine.id,
      );
    }
  });

  test('an engine with no compatible source is dropped but visible', () {
    const svOnly = LintProject(
      name: 'design',
      rootPath: '/repo',
      sourceFiles: <String>['/repo/top.sv'],
    );
    final plan = planner.plan(
      project: svOnly,
      registry: registry,
      binaryConfigFor: binaryFor,
    );
    expect(plan.pairs.map((p) => p.engine.id), isNot(contains('ghdl')));
    expect(plan.enginesWithoutSources, <String>['ghdl']);
    expect(plan.routing.selectionFor('ghdl')!.sourcesTotal, 1);
  });

  test('engineIdsOverride replaces the project selection', () {
    const narrowed = LintProject(
      name: 'design',
      rootPath: '/repo',
      sourceFiles: <String>['/repo/top.sv'],
      enabledEngineIds: <String>['verilator', 'slang'],
    );
    final plan = planner.plan(
      project: narrowed,
      registry: registry,
      binaryConfigFor: binaryFor,
      engineIdsOverride: <String>['slang'],
    );
    expect(plan.pairs.map((p) => p.engine.id), <String>['slang']);
  });

  test('an empty enabledEngineIds means every registered engine', () {
    final plan = planner.plan(
      project: project,
      registry: registry,
      binaryConfigFor: binaryFor,
    );
    expect(plan.pairs.map((p) => p.engine.id), hasLength(3));
  });

  test('unknown ids are reported, not silently dropped', () {
    final plan = planner.plan(
      project: project,
      registry: registry,
      binaryConfigFor: binaryFor,
      engineIdsOverride: <String>['verilator', 'verlator'],
    );
    expect(plan.unknownEngineIds, <String>['verlator']);
    expect(plan.pairs.map((p) => p.engine.id), <String>['verilator']);
  });

  test('topModuleOverride wins over the project topModule', () {
    const withTop = LintProject(
      name: 'design',
      rootPath: '/repo',
      sourceFiles: <String>['/repo/top.sv'],
      topModule: 'committed',
    );
    final overridden = planner.plan(
      project: withTop,
      registry: registry,
      binaryConfigFor: binaryFor,
      topModuleOverride: 'ci_top',
    );
    expect(overridden.pairs.first.request.topModule, 'ci_top');

    final untouched = planner.plan(
      project: withTop,
      registry: registry,
      binaryConfigFor: binaryFor,
    );
    expect(untouched.pairs.first.request.topModule, 'committed');

    final emptyOverride = planner.plan(
      project: withTop,
      registry: registry,
      binaryConfigFor: binaryFor,
      topModuleOverride: '',
    );
    expect(emptyOverride.pairs.first.request.topModule, 'committed');
  });

  test('per-source-file language declarations are honored', () {
    // A `.v` file explicitly declared VHDL must go to GHDL, not
    // Verilator — extension-based inference is only the fallback.
    const declared = LintProject(
      name: 'design',
      rootPath: '/repo',
      sourceFiles: <String>['/repo/legacy.v'],
      sourceFileLanguages: <String, ProjectSourceFileLanguage>{
        '/repo/legacy.v': ProjectSourceFileLanguage.vhdl,
      },
    );
    final plan = planner.plan(
      project: declared,
      registry: registry,
      binaryConfigFor: binaryFor,
    );
    expect(plan.pairs.map((p) => p.engine.id), <String>['ghdl']);
  });

  test('the request carries includes, defines and per-engine options', () {
    const rich = LintProject(
      name: 'design',
      rootPath: '/repo',
      sourceFiles: <String>['/repo/top.sv'],
      includePaths: <String>['/repo/inc'],
      defines: <String, String>{'SYNTHESIS': '1'},
      enabledEngineIds: <String>['verilator'],
      perEngineOptions: <String, Map<String, Object?>>{
        'verilator': <String, Object?>{'wall': true},
      },
    );
    final request = planner
        .plan(
          project: rich,
          registry: registry,
          binaryConfigFor: binaryFor,
        )
        .pairs
        .single
        .request;
    expect(request.includePaths, <String>['/repo/inc']);
    expect(request.defines, <String, String>{'SYNTHESIS': '1'});
    expect(request.options, <String, Object?>{'wall': true});
    expect(request.binary, bundled);
  });

  test('a single-language engine declares its own request language', () {
    final plan = planner.plan(
      project: project,
      registry: registry,
      binaryConfigFor: binaryFor,
    );
    final ghdl = plan.pairs.firstWhere((p) => p.engine.id == 'ghdl');
    expect(ghdl.request.language, HdlLanguage.vhdl);
    final verilator = plan.pairs.firstWhere((p) => p.engine.id == 'verilator');
    expect(verilator.request.language, HdlLanguage.mixed);
  });
}
