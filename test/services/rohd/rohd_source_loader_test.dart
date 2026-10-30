// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/rohd_dart_source.dart';
import 'package:lintcrux/services/rohd/rohd_source_loader.dart';

import '../../support/rohd_fixture_package.dart';

RohdDartSource? _at(RohdSourceMaps maps, String file, int line, {String? m}) =>
    maps.byFile.values.isEmpty
    ? null
    : maps.byFile[file]?.lookup(line, message: m);

void main() {
  late RohdFixturePackage pkg;
  tearDown(() => pkg.dispose());

  group('the sidecar next to the file', () {
    test(
      'Top.flc.json beside top.sv: names the Dart file, normalized',
      () async {
        pkg = RohdFixturePackage.create();
        final sv = pkg.inBuild('top.sv');
        final maps = await loadRohdSourceMaps(
          sourceFiles: [sv],
          projectRoot: pkg.root,
        );
        expect(maps.warnings, isEmpty);
        final source = _at(maps, sv, 54)!;
        // `.dart_tool/../lib/design.dart` is normalized and resolved to the
        // package that holds it, though the sidecar says /work/rohd_fixture.
        expect(source.primary.file, pkg.path('lib/design.dart'));
        expect(source.primary.line, 59);
        expect(source.primary.column, 19);
        expect(source.kind, RohdDartSourceKind.exact);
        expect(source.symbol, 'gated');
      },
    );

    test(
      'the one-module-per-file layout maps each file by its own name',
      () async {
        pkg = RohdFixturePackage.create(perModule: true);
        final top = pkg.inBuild('Top.sv');
        final adder = pkg.inBuild('Adder.sv');
        final maps = await loadRohdSourceMaps(
          sourceFiles: [top, adder, pkg.inBuild('Reg.sv')],
          projectRoot: pkg.root,
        );
        expect(maps.warnings, isEmpty);
        expect(maps.byFile.keys, hasLength(3));
        // Top.sv line 21 is `gated = sum;`.
        expect(_at(maps, top, 21)!.primary.line, 59);
        // Adder.sv declares `partial` and drives `sum`.
        final adderSource = _at(maps, adder, 8, m: 'sum');
        expect(adderSource, isNotNull);
      },
    );

    test('a file with no sidecar and no comments has no index', () async {
      pkg = RohdFixturePackage.create(sidecar: false);
      final sv = pkg.inBuild('plain.sv');
      File(sv).writeAsStringSync('module m;\nendmodule\n');
      final maps = await loadRohdSourceMaps(
        sourceFiles: [sv, pkg.path('lib/design.dart')],
        projectRoot: pkg.root,
      );
      expect(maps.byFile, isEmpty);
      expect(maps.warnings, isEmpty);
    });

    test('without a sidecar the inline comments still map the file', () async {
      pkg = RohdFixturePackage.create(sidecar: false);
      final sv = pkg.inBuild('top.sv');
      final maps = await loadRohdSourceMaps(
        sourceFiles: [sv],
        projectRoot: pkg.root,
      );
      final source = _at(maps, sv, 61)!;
      expect(source.fromInlineComment, isTrue);
      expect(source.primary.file, pkg.path('lib/design.dart'));
      expect(source.primary.line, 21);
      expect(source.calledFrom.single.line, 58);
    });
  });

  group('a sidecar named in the project', () {
    test('a path relative to the project root', () async {
      pkg = RohdFixturePackage.create();
      final elsewhere = Directory(pkg.path('trace'))..createSync();
      File(pkg.inBuild('Top.flc.json')).renameSync(
        '${elsewhere.path}/Top.flc.json',
      );
      final sv = pkg.inBuild('top.sv');
      final without = await loadRohdSourceMaps(
        sourceFiles: [sv],
        projectRoot: pkg.root,
      );
      // Nothing next to it: only the inline comments, so a read has no
      // sidecar-backed answer.
      expect(_at(without, sv, 54)!.fromInlineComment, isTrue);

      final maps = await loadRohdSourceMaps(
        sourceFiles: [sv],
        projectRoot: pkg.root,
        options: {kRohdSidecarOption: 'trace/Top.flc.json'},
      );
      expect(_at(maps, sv, 54)!.fromInlineComment, isFalse);
      expect(_at(maps, sv, 54)!.symbol, 'gated');
    });

    test('a directory, and a list', () async {
      pkg = RohdFixturePackage.create();
      final elsewhere = Directory(pkg.path('trace'))..createSync();
      File(pkg.inBuild('Top.flc.json')).renameSync(
        '${elsewhere.path}/Top.flc.json',
      );
      final sv = pkg.inBuild('top.sv');
      for (final value in <Object>[
        'trace',
        ['nothing/here.flc.json', 'trace'],
      ]) {
        final maps = await loadRohdSourceMaps(
          sourceFiles: [sv],
          projectRoot: pkg.root,
          options: {kRohdSidecarOption: value},
        );
        expect(_at(maps, sv, 54)!.symbol, 'gated', reason: '$value');
      }
    });
  });

  group('a sidecar that cannot be used never fails the run', () {
    test(
      'an unknown version: a warning, the inline comments still serve',
      () async {
        pkg = RohdFixturePackage.create();
        File(pkg.inBuild('Top.flc.json')).writeAsStringSync(
          '{"version": 7, "files": [], "modules": {}}',
        );
        final sv = pkg.inBuild('top.sv');
        final maps = await loadRohdSourceMaps(
          sourceFiles: [sv],
          projectRoot: pkg.root,
        );
        expect(maps.warnings, hasLength(1));
        expect(maps.warnings.single, contains('version 7'));
        expect(maps.warnings.single, contains('Top.flc.json'));
        expect(_at(maps, sv, 61)!.fromInlineComment, isTrue);
      },
    );

    test('a truncated sidecar and an unreadable one each warn once', () async {
      pkg = RohdFixturePackage.create();
      File(pkg.inBuild('Top.flc.json')).writeAsStringSync('{"version": 6, "fi');
      final sv = pkg.inBuild('top.sv');
      final a = pkg.inBuild('a.sv');
      File(a).writeAsStringSync('module a;\nendmodule\n');
      final maps = await loadRohdSourceMaps(
        sourceFiles: [sv, a],
        projectRoot: pkg.root,
        options: {kRohdSidecarOption: 'missing/never.flc.json'},
      );
      // Named for `top.sv`, so expected to be good: warned about. The missing
      // configured file is warned about for each file that asked for it, but
      // once: the same path is read once.
      expect(
        maps.warnings.where((w) => w.contains('Top.flc.json')),
        hasLength(1),
      );
      expect(
        maps.warnings.where((w) => w.contains('never.flc.json')),
        hasLength(1),
      );
    });

    test(
      'a stranger .flc.json that describes another file is silent',
      () async {
        pkg = RohdFixturePackage.create();
        File(
          pkg.inBuild('other.flc.json'),
        ).writeAsStringSync('{"version": 99}');
        final sv = pkg.inBuild('top.sv');
        final maps = await loadRohdSourceMaps(
          sourceFiles: [sv],
          projectRoot: pkg.root,
        );
        expect(maps.warnings, isEmpty);
        expect(_at(maps, sv, 54)!.symbol, 'gated');
      },
    );

    test('a source file that has gone, and non-SystemVerilog files', () async {
      pkg = RohdFixturePackage.create();
      final maps = await loadRohdSourceMaps(
        sourceFiles: [
          pkg.inBuild('gone.sv'),
          pkg.path('lib/design.dart'),
          pkg.path('pubspec.yaml'),
        ],
        projectRoot: pkg.root,
      );
      expect(maps.byFile, isEmpty);
      expect(maps.warnings, isEmpty);
    });
  });
}
