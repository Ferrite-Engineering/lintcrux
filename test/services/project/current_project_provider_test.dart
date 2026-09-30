// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/project/project_file_codec.dart';
import 'package:lintcrux/services/project/project_path_resolver.dart';
import 'package:path/path.dart' as p;

void main() {
  group('currentProjectProvider', () {
    test('initial state is null (no project loaded)', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(currentProjectProvider), isNull);
    });

    test('load() installs a project', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      const project = LintProject(name: 'p', rootPath: '/r');
      c.read(currentProjectProvider.notifier).load(project);
      expect(c.read(currentProjectProvider), project);
    });

    test('clear() drops the loaded project', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      const project = LintProject(name: 'p', rootPath: '/r');
      c.read(currentProjectProvider.notifier)
        ..load(project)
        ..clear();
      expect(c.read(currentProjectProvider), isNull);
    });

    test('load() replaces a previously loaded project', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      const a = LintProject(name: 'a', rootPath: '/a');
      const b = LintProject(name: 'b', rootPath: '/b');
      c.read(currentProjectProvider.notifier)
        ..load(a)
        ..load(b);
      expect(c.read(currentProjectProvider), b);
    });
  });
  group('saveSeverityOverride', () {
    late Directory tmp;
    late String projectFile;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lintcrux_severity_save_');
      projectFile = p.join(tmp.path, 'soc.lintcrux');
      // A committed, portable project: relative root and sources, plus an
      // override the user did not touch.
      File(projectFile).writeAsStringSync(
        jsonEncode(<String, Object?>{
          'version': 1,
          'name': 'soc',
          'rootPath': '.',
          'sourceFiles': <String>['rtl/top.sv'],
          'severityOverrides': <String, String>{'verible/line-length': 'none'},
        }),
      );
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    ProviderContainer loaded() {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final authored = const ProjectFileCodec().decode(
        File(projectFile).readAsStringSync(),
      );
      c
          .read(currentProjectProvider.notifier)
          .load(
            resolveProjectPaths(authored, tmp.path),
            projectFilePath: projectFile,
          );
      return c;
    }

    Map<String, dynamic> onDisk() =>
        jsonDecode(File(projectFile).readAsStringSync())
            as Map<String, dynamic>;

    test('applies to the tab and is written to the project file', () async {
      final c = loaded();
      await c
          .read(currentProjectProvider.notifier)
          .saveSeverityOverride('verilator/UNUSEDSIGNAL', Severity.note);

      expect(
        c.read(currentProjectProvider)!.severityOverrides,
        containsPair('verilator/UNUSEDSIGNAL', Severity.note),
      );
      final file = onDisk();
      expect(file['severityOverrides'], {
        'verible/line-length': 'none',
        'verilator/UNUSEDSIGNAL': 'note',
      });
      expect(
        file['rootPath'],
        '.',
        reason: 'the file keeps its portable, authored paths',
      );
      expect(file['sourceFiles'], ['rtl/top.sv']);
    });

    test('removing an override removes it from the file', () async {
      final c = loaded();
      await c
          .read(currentProjectProvider.notifier)
          .saveSeverityOverride('verible/line-length', null);
      expect(onDisk()['severityOverrides'], anyOf(isNull, isEmpty));
    });

    test('rapid edits all land', () async {
      final notifier = loaded().read(currentProjectProvider.notifier);
      await Future.wait(<Future<void>>[
        notifier.saveSeverityOverride('a/ONE', Severity.error),
        notifier.saveSeverityOverride('a/TWO', Severity.warning),
        notifier.saveSeverityOverride('a/THREE', Severity.note),
      ]);
      expect(
        (onDisk()['severityOverrides'] as Map).keys,
        containsAll(<String>['a/ONE', 'a/TWO', 'a/THREE']),
      );
    });

    test('an unwritable file is reported to the caller', () async {
      final notifier = loaded().read(currentProjectProvider.notifier);
      File(projectFile).deleteSync();
      await expectLater(
        notifier.saveSeverityOverride('a/ONE', Severity.error),
        throwsA(isA<ProjectFileException>()),
      );
    });

    test('a project loaded without a file still applies in memory', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(currentProjectProvider.notifier)
          .load(const LintProject(name: 'p', rootPath: '/r'));
      await c
          .read(currentProjectProvider.notifier)
          .saveSeverityOverride('a/ONE', Severity.error);
      expect(
        c.read(currentProjectProvider)!.severityOverrides['a/ONE'],
        Severity.error,
      );
    });
  });
}
