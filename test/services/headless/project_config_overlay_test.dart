// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/services/headless/project_config_overlay.dart';
import 'package:path/path.dart' as p;

void main() {
  const overlay = ProjectConfigOverlay();

  // The overlay normalizes the paths it resolves, so a rooted path spelled
  // with `/` comes back in the host separator: `/repo` on POSIX, `\repo` on
  // Windows. Spell the base the same way so the expectations are host-shaped.
  final base = p.normalize('/repo');

  final project = LintProject(
    name: 'design',
    rootPath: base,
    sourceFiles: <String>[p.join(base, 'rtl', 'top.sv')],
    includePaths: <String>[p.join(base, 'rtl')],
    defines: const <String, String>{'ORIGINAL': '1'},
    topModule: 'top',
    enabledEngineIds: const <String>['verilator', 'verible'],
    severityOverrides: const <String, Severity>{'a/B': Severity.error},
  );

  LintProject apply(Map<String, dynamic> map) =>
      overlay.apply(project, map, base: base);

  group('present keys replace, absent keys are untouched', () {
    test('an empty overlay changes nothing', () {
      expect(apply(const <String, dynamic>{}), project);
    });

    test('enabledEngineIds is replaced wholesale', () {
      final out = apply(const <String, dynamic>{
        'enabledEngineIds': <String>['verilator'],
      });
      expect(out.enabledEngineIds, <String>['verilator']);
      // Everything else survives.
      expect(out.defines, project.defines);
      expect(out.topModule, project.topModule);
    });

    test('defines are replaced, not merged', () {
      final out = apply(const <String, dynamic>{
        'defines': <String, dynamic>{'SYNTHESIS': '1'},
      });
      expect(out.defines, <String, String>{'SYNTHESIS': '1'});
      expect(out.defines.containsKey('ORIGINAL'), isFalse);
    });

    test('severityOverrides parse severity names', () {
      final out = apply(const <String, dynamic>{
        'severityOverrides': <String, dynamic>{
          'verilator/UNUSEDSIGNAL': 'note',
        },
      });
      expect(out.severityOverrides, <String, Severity>{
        'verilator/UNUSEDSIGNAL': Severity.note,
      });
    });

    test('language accepts the enum spelling in any case', () {
      expect(
        apply(const <String, dynamic>{'language': 'systemVerilog'}).language,
        HdlLanguage.systemVerilog,
      );
      expect(
        apply(const <String, dynamic>{'language': 'vhdl'}).language,
        HdlLanguage.vhdl,
      );
    });

    test('relative paths resolve against the overlay directory', () {
      final out = apply(const <String, dynamic>{
        'sourceFiles': <String>['other/a.sv'],
        'includePaths': <String>['inc'],
      });
      expect(out.sourceFiles.single, p.join(base, 'other', 'a.sv'));
      expect(out.includePaths.single, p.join(base, 'inc'));
    });
  });

  group('malformed overlays fail loudly', () {
    // A CI job whose severity overrides silently did not apply reports
    // the wrong answer. Every shape error must throw.

    test('an unknown key is rejected and lists the legal ones', () {
      expect(
        () => apply(const <String, dynamic>{'name': 'renamed'}),
        throwsA(
          isA<ProjectConfigOverlayException>().having(
            (e) => e.message,
            'message',
            allOf(contains('name'), contains('Overlayable keys')),
          ),
        ),
      );
    });

    test('name / rootPath are deliberately not overlayable', () {
      for (final key in <String>['name', 'rootPath']) {
        expect(
          () => apply(<String, dynamic>{key: 'x'}),
          throwsA(isA<ProjectConfigOverlayException>()),
          reason: key,
        );
      }
    });

    test('a wrong-typed value is rejected', () {
      expect(
        () => apply(const <String, dynamic>{'sourceFiles': 'a.sv'}),
        throwsA(isA<ProjectConfigOverlayException>()),
      );
      expect(
        () => apply(const <String, dynamic>{'topModule': 42}),
        throwsA(isA<ProjectConfigOverlayException>()),
      );
      expect(
        () => apply(const <String, dynamic>{'perEngineOptions': 3}),
        throwsA(isA<ProjectConfigOverlayException>()),
      );
    });

    test('an unknown severity names the legal set', () {
      expect(
        () => apply(const <String, dynamic>{
          'severityOverrides': <String, dynamic>{'a/B': 'critical'},
        }),
        throwsA(
          isA<ProjectConfigOverlayException>().having(
            (e) => e.message,
            'message',
            contains('warning'),
          ),
        ),
      );
    });

    test('an unknown language names the legal set', () {
      expect(
        () => apply(const <String, dynamic>{'language': 'chisel'}),
        throwsA(
          isA<ProjectConfigOverlayException>().having(
            (e) => e.message,
            'message',
            contains('systemVerilog'),
          ),
        ),
      );
    });
  });

  group('applyFile', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lintcrux_overlay_');
    });
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('reads a JSON overlay off disk', () async {
      final file = File(p.join(tmp.path, 'ci.lintcrux'))
        ..writeAsStringSync(
          jsonEncode(<String, dynamic>{
            'enabledEngineIds': <String>['verilator'],
          }),
        );
      final out = await overlay.applyFile(project, file.path);
      expect(out.enabledEngineIds, <String>['verilator']);
    });

    test('a missing file throws rather than being ignored', () {
      expect(
        () => overlay.applyFile(project, p.join(tmp.path, 'nope.lintcrux')),
        throwsA(isA<ProjectConfigOverlayException>()),
      );
    });

    test('invalid JSON throws', () {
      final file = File(p.join(tmp.path, 'ci.lintcrux'))
        ..writeAsStringSync('{ not json');
      expect(
        () => overlay.applyFile(project, file.path),
        throwsA(isA<ProjectConfigOverlayException>()),
      );
    });

    test('a JSON array (not an object) throws', () {
      final file = File(p.join(tmp.path, 'ci.lintcrux'))
        ..writeAsStringSync('[]');
      expect(
        () => overlay.applyFile(project, file.path),
        throwsA(isA<ProjectConfigOverlayException>()),
      );
    });
  });
}
