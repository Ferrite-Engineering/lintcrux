// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/project_source_file.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/engine_language_router.dart';

void main() {
  group('EngineLanguageRouter', () {
    test('verilator-only engine drops .vhd sources', () {
      const router = EngineLanguageRouter();
      const project = LintProject(
        name: 'p',
        rootPath: '/p',
        sourceFiles: ['a.sv', 'b.vhd', 'c.v'],
      );
      final engines = <LintEngine>[
        _FakeEngine(
          id: 'verilator',
          langs: {HdlLanguage.verilog, HdlLanguage.systemVerilog},
        ),
      ];
      final routing = router.computeRouting(
        project: project,
        engines: engines,
      );
      final sel = routing.selectionFor('verilator')!;
      expect(sel.sourcesUsed, ['a.sv', 'c.v']);
      expect(sel.sourcesDropped, ['b.vhd']);
      expect(sel.sourcesTotal, 3);
      expect(sel.requestLanguage, HdlLanguage.systemVerilog);
    });

    test('ghdl gets only .vhd sources', () {
      const router = EngineLanguageRouter();
      const project = LintProject(
        name: 'p',
        rootPath: '/p',
        sourceFiles: ['a.sv', 'b.vhd', 'c.vhdl'],
      );
      final engines = <LintEngine>[
        _FakeEngine(id: 'ghdl', langs: {HdlLanguage.vhdl}),
      ];
      final routing = router.computeRouting(
        project: project,
        engines: engines,
      );
      final sel = routing.selectionFor('ghdl')!;
      expect(sel.sourcesUsed, ['b.vhd', 'c.vhdl']);
      expect(sel.sourcesDropped, ['a.sv']);
      expect(sel.requestLanguage, HdlLanguage.vhdl);
    });

    test('per-file language override takes precedence over extension', () {
      const router = EngineLanguageRouter();
      const project = LintProject(
        name: 'p',
        rootPath: '/p',
        sourceFiles: ['a.v', 'b.v'],
        // `a.v` is declared SystemVerilog despite the .v extension
        // (legacy `.v` files often contain SystemVerilog).
        sourceFileLanguages: {
          'a.v': ProjectSourceFileLanguage.systemVerilog,
          'b.v': ProjectSourceFileLanguage.verilog,
        },
      );
      final engines = <LintEngine>[
        _FakeEngine(
          id: 'slang',
          langs: {HdlLanguage.systemVerilog},
        ),
      ];
      final routing = router.computeRouting(
        project: project,
        engines: engines,
      );
      final sel = routing.selectionFor('slang')!;
      // Only `a.v` (declared SV) survives the routing — `b.v` is
      // strict Verilog which Slang doesn't accept here.
      expect(sel.sourcesUsed, ['a.v']);
      expect(sel.sourcesDropped, ['b.v']);
    });

    test('returns empty selection when no source files match', () {
      const router = EngineLanguageRouter();
      const project = LintProject(
        name: 'p',
        rootPath: '/p',
        sourceFiles: ['a.vhd', 'b.vhd'],
      );
      final engines = <LintEngine>[
        _FakeEngine(id: 'verilator', langs: {HdlLanguage.verilog}),
      ];
      final routing = router.computeRouting(
        project: project,
        engines: engines,
      );
      final sel = routing.selectionFor('verilator')!;
      expect(sel.sourcesUsed, isEmpty);
      expect(sel.hasAnySource, isFalse);
      expect(sel.sourcesDropped, ['a.vhd', 'b.vhd']);
      expect(sel.sourcesTotal, 2);
    });

    test('mixed project routes the right subset to each engine', () {
      const router = EngineLanguageRouter();
      const project = LintProject(
        name: 'p',
        rootPath: '/p',
        sourceFiles: ['a.sv', 'b.vhd', 'c.v', 'd.vhdl'],
        language: HdlLanguage.mixed,
      );
      final engines = <LintEngine>[
        _FakeEngine(
          id: 'verilator',
          langs: {HdlLanguage.verilog, HdlLanguage.systemVerilog},
        ),
        _FakeEngine(id: 'ghdl', langs: {HdlLanguage.vhdl}),
      ];
      final routing = router.computeRouting(
        project: project,
        engines: engines,
      );
      expect(
        routing.selectionFor('verilator')!.sourcesUsed,
        ['a.sv', 'c.v'],
      );
      expect(
        routing.selectionFor('ghdl')!.sourcesUsed,
        ['b.vhd', 'd.vhdl'],
      );
      // Verilator gets its single language even with a mixed project,
      // because it only supports SystemVerilog + Verilog.
      expect(
        routing.selectionFor('verilator')!.requestLanguage,
        // Verilator declares 2 languages → falls back to project-level
        // which is `mixed`.
        HdlLanguage.mixed,
      );
      expect(routing.selectionFor('ghdl')!.requestLanguage, HdlLanguage.vhdl);
    });

    test('engine declaring mixed-language accepts every source', () {
      const router = EngineLanguageRouter();
      const project = LintProject(
        name: 'p',
        rootPath: '/p',
        sourceFiles: ['a.sv', 'b.vhd'],
      );
      final engines = <LintEngine>[
        _FakeEngine(id: 'super', langs: {HdlLanguage.mixed}),
      ];
      final routing = router.computeRouting(
        project: project,
        engines: engines,
      );
      expect(
        routing.selectionFor('super')!.sourcesUsed,
        ['a.sv', 'b.vhd'],
      );
    });
  });
}

class _FakeEngine implements LintEngine {
  _FakeEngine({required this.id, required Set<HdlLanguage> langs})
    : capabilities = EngineCapabilities(supportedLanguages: langs);

  @override
  final String id;

  @override
  String get displayName => id;

  @override
  final EngineCapabilities capabilities;

  @override
  void cancel() {}

  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async => null;

  @override
  Stream<Violation> run(LintRunRequest request) async* {}

  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) => run(request);
}
