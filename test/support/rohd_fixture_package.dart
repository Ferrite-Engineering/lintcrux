// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:path/path.dart' as p;

/// Where the committed ROHD fixtures are; see `verification/fixtures/rohd`.
const String kRohdFixtureDir = 'verification/fixtures/rohd';

/// A Dart package on disk that looks the way the machine that ran the design
/// left it: `pubspec.yaml`, the design's `lib/design.dart`, and a `build/`
/// folder holding the generated SystemVerilog and its sidecar.
///
/// The fixtures were generated in `/work/rohd_fixture`, a folder that does not
/// exist here, so resolving the Dart paths has to find the package root from
/// where the files were put, as it will for a user who moved them.
class RohdFixturePackage {
  RohdFixturePackage._(this.root);

  /// Creates the package in a fresh temporary directory.
  ///
  /// [sidecar] copies `Top.flc.json` beside the SystemVerilog; [perModule]
  /// uses the one-file-per-module layout.
  static RohdFixturePackage create({
    bool sidecar = true,
    bool perModule = false,
  }) {
    final root = Directory.systemTemp.createTempSync('lintcrux_rohd_').path;
    final pkg = RohdFixturePackage._(root);
    File(
      p.join(root, 'pubspec.yaml'),
    ).writeAsStringSync('name: rohd_fixture\n');
    Directory(p.join(root, 'lib')).createSync();
    File(
      p.join(kRohdFixtureDir, 'generator', 'design.dart.txt'),
    ).copySync(p.join(root, 'lib', 'design.dart'));
    final build = Directory(p.join(root, 'build'))..createSync();
    if (perModule) {
      for (final name in <String>['Top.sv', 'Adder.sv', 'Reg.sv']) {
        File(
          p.join(kRohdFixtureDir, 'per_module', name),
        ).copySync(p.join(build.path, name));
      }
      if (sidecar) {
        File(
          p.join(kRohdFixtureDir, 'per_module', 'Top.flc.json'),
        ).copySync(p.join(build.path, 'Top.flc.json'));
      }
    } else {
      File(
        p.join(kRohdFixtureDir, 'top.sv'),
      ).copySync(p.join(build.path, 'top.sv'));
      if (sidecar) {
        File(
          p.join(kRohdFixtureDir, 'Top.flc.json'),
        ).copySync(p.join(build.path, 'Top.flc.json'));
      }
    }
    return pkg;
  }

  /// The package root.
  final String root;

  /// The generated `build/` folder.
  String get build => p.join(root, 'build');

  /// A path under [build].
  String inBuild(String name) => p.join(build, name);

  /// A path under the package.
  String path(String relative) => p.join(root, relative);

  /// Removes the package.
  void dispose() {
    final dir = Directory(root);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}
