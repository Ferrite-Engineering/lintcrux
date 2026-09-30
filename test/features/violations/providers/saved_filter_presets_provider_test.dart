// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/named_filter_preset.dart';
import 'package:lintcrux/features/violations/models/saved_filter_presets_state.dart';
import 'package:lintcrux/features/violations/providers/saved_filter_presets_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/project/project_file_codec.dart';
import 'package:lintcrux/services/project/project_path_resolver.dart';
import 'package:path/path.dart' as p;

void main() {
  group('SavedFilterPresetsNotifier', () {
    test('initial state is empty', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(
        c.read(savedFilterPresetsProvider),
        SavedFilterPresetsState.empty,
      );
    });

    test('save adds a new preset', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      const p = NamedFilterPreset(name: 'p1');
      c.read(savedFilterPresetsProvider.notifier).save(p);
      expect(c.read(savedFilterPresetsProvider).presets, [p]);
    });

    test('save replaces a preset with the same name', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      const p = NamedFilterPreset(name: 'p1');
      const p2 = NamedFilterPreset(
        name: 'p1',
        severities: {Severity.error},
      );
      c.read(savedFilterPresetsProvider.notifier)
        ..save(p)
        ..save(p2);
      final result = c.read(savedFilterPresetsProvider).presets;
      expect(result, hasLength(1));
      expect(result.single.severities, {Severity.error});
    });

    test('delete removes the named preset', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      const a = NamedFilterPreset(name: 'a');
      const b = NamedFilterPreset(name: 'b');
      c.read(savedFilterPresetsProvider.notifier)
        ..save(a)
        ..save(b)
        ..delete('a');
      expect(c.read(savedFilterPresetsProvider).presets, [b]);
    });

    test('delete clears the active preset if it matches', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      const p = NamedFilterPreset(name: 'p', severities: {Severity.error});
      c.read(savedFilterPresetsProvider.notifier)
        ..save(p)
        ..activate('p');
      expect(c.read(savedFilterPresetsProvider).activePresetName, 'p');
      c.read(savedFilterPresetsProvider.notifier).delete('p');
      expect(c.read(savedFilterPresetsProvider).activePresetName, isNull);
    });

    test('activate(null) clears the active preset', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      const p = NamedFilterPreset(name: 'p');
      c.read(savedFilterPresetsProvider.notifier)
        ..save(p)
        ..activate('p');
      c.read(savedFilterPresetsProvider.notifier).activate(null);
      expect(c.read(savedFilterPresetsProvider).activePresetName, isNull);
    });

    test('activate applies the preset filters to the violation table', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      const p = NamedFilterPreset(
        name: 'p',
        severities: {Severity.error},
        engineIds: {'verilator'},
        ruleSubstring: 'WIDTH',
        fileGlob: '*.sv',
      );
      c.read(savedFilterPresetsProvider.notifier)
        ..save(p)
        ..activate('p');
      final table = c.read(violationTableStateProvider);
      expect(table.severities, {Severity.error});
      expect(table.engineIds, {'verilator'});
      expect(table.ruleSubstring, 'WIDTH');
      expect(table.fileGlob, '*.sv');
    });

    test('activate is a no-op when the name is not found', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(savedFilterPresetsProvider.notifier).activate('does-not-exist');
      expect(c.read(savedFilterPresetsProvider).activePresetName, isNull);
    });

    test('replace swaps the entire state', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      const a = NamedFilterPreset(name: 'a');
      const next = SavedFilterPresetsState(
        presets: [a],
        activePresetName: 'a',
      );
      c.read(savedFilterPresetsProvider.notifier).replace(next);
      expect(c.read(savedFilterPresetsProvider), next);
    });

    test('extension toPreset captures the current table state', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(violationTableStateProvider.notifier)
        ..toggleSeverity(Severity.error)
        ..setRuleSubstring('UNUSED');
      final preset = c.read(violationTableStateProvider).toPreset('My filter');
      expect(preset.name, 'My filter');
      expect(preset.severities, {Severity.error});
      expect(preset.ruleSubstring, 'UNUSED');
    });
  });
  group('SavedFilterPresetsNotifier with a project file', () {
    late Directory tmp;
    late String projectFile;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lintcrux_presets_');
      projectFile = p.join(tmp.path, 'soc.lintcrux');
      File(projectFile).writeAsStringSync(
        jsonEncode(<String, Object?>{
          'version': 1,
          'name': 'soc',
          'rootPath': '.',
          'sourceFiles': <String>['rtl/top.sv'],
          'filterPresets': <Object?>[
            const NamedFilterPreset(
              name: 'committed',
              severities: {Severity.error},
            ).toJson(),
          ],
        }),
      );
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    ProviderContainer openProject() {
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

    List<String> namesOnDisk() => <String>[
      for (final preset
          in (jsonDecode(File(projectFile).readAsStringSync())
                  as Map<String, dynamic>)['filterPresets']
              as List)
        (preset as Map<String, dynamic>)['name'] as String,
    ];

    test('presets committed in the project file are listed', () {
      final c = openProject();
      expect(
        c.read(savedFilterPresetsProvider).presets.map((p) => p.name),
        ['committed'],
      );
    });

    test('a saved preset is written to the project file', () async {
      final c = openProject();
      final notifier = c.read(savedFilterPresetsProvider.notifier)
        ..save(const NamedFilterPreset(name: 'mine', ruleSubstring: 'WIDTH'));
      await notifier.persisted;
      expect(namesOnDisk(), ['committed', 'mine']);
      expect(
        (jsonDecode(File(projectFile).readAsStringSync()) as Map)['rootPath'],
        '.',
        reason: 'the file keeps its authored, portable paths',
      );
    });

    test('a new tab over the same project still lists it', () async {
      final first = openProject();
      final notifier = first.read(savedFilterPresetsProvider.notifier)
        ..save(const NamedFilterPreset(name: 'mine'));
      await notifier.persisted;

      final reopened = openProject();
      expect(
        reopened.read(savedFilterPresetsProvider).presets.map((p) => p.name),
        ['committed', 'mine'],
      );
    });

    test('a deleted preset is removed from the file', () async {
      final c = openProject();
      final notifier = c.read(savedFilterPresetsProvider.notifier)
        ..delete('committed');
      await notifier.persisted;
      expect(namesOnDisk(), isEmpty);
    });

    test('the active selection survives an unrelated project change', () {
      final c = openProject();
      c.read(savedFilterPresetsProvider.notifier).activate('committed');
      c
          .read(currentProjectProvider.notifier)
          .setSeverityOverride('verilator/WIDTH', Severity.note);
      expect(c.read(savedFilterPresetsProvider).activePresetName, 'committed');
    });

    test('a write failure is reported through persisted', () async {
      final c = openProject();
      File(projectFile).deleteSync();
      final notifier = c.read(savedFilterPresetsProvider.notifier)
        ..save(const NamedFilterPreset(name: 'mine'));
      await expectLater(
        notifier.persisted,
        throwsA(isA<ProjectFileException>()),
      );
    });
  });
}
