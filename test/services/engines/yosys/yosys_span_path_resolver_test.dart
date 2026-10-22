// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/services/engines/yosys/yosys_elaboration.dart';
import 'package:path/path.dart' as p;

// yosys-slang names each `src` file relative to the directory Yosys ran in,
// with or without --diag-abs-paths (measured on OSS CAD Suite 2026-10-21).
// A finding keyed on `rtl/top.sv` would not match a waiver or a baseline
// written against `/project/rtl/top.sv`, so every span is turned back into
// the project's own name before a finding is built.

LintRunRequest _request(
  String root,
  List<String> sources, {
  Map<String, Object?> options = const <String, Object?>{},
}) => LintRunRequest(
  sourceFiles: sources,
  binary: const EngineBinaryConfig.system(),
  language: HdlLanguage.systemVerilog,
  projectRoot: root,
  options: options,
);

void main() {
  late Directory temp;
  late String root;
  late String top;
  late String pkg;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('span-resolver-');
    root = p.join(temp.path, 'project');
    top = p.join(root, 'rtl', 'top.sv');
    pkg = p.join(root, 'rtl', 'pkg', 'types_pkg.sv');
    File(top).createSync(recursive: true);
    File(pkg).createSync(recursive: true);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('an absolute file, as the built-in reader writes it, is unchanged', () {
    final paths = YosysSpanPathResolver(_request(root, [top]));
    expect(paths.resolve(top), top);
  });

  test('a relative file is the source it names, spelled as the project '
      'spells it', () {
    final paths = YosysSpanPathResolver(_request(root, [top, pkg]));
    expect(paths.resolve(p.join('rtl', 'top.sv')), top);
    expect(paths.resolve(p.join('rtl', 'pkg', 'types_pkg.sv')), pkg);
  });

  test('a relative file is resolved against the workingDirectory option', () {
    final paths = YosysSpanPathResolver(
      _request(root, [top], options: const {'workingDirectory': 'sim'}),
    );
    expect(paths.resolve(p.join('..', 'rtl', 'top.sv')), top);
  });

  test('a file outside the source list, such as an included header, comes '
      'back absolute under the run directory', () {
    final paths = YosysSpanPathResolver(_request(root, [top]));
    expect(
      paths.resolve(p.join('rtl', 'inc', 'defs.svh')),
      p.join(root, 'rtl', 'inc', 'defs.svh'),
    );
  });

  test('a name computed from the canonical run directory still maps to the '
      'project spelling when the project is reached through a link', () {
    // The project is opened through a link; Yosys's own working directory
    // is the link's target, so a relative name may be relative to that.
    final link = Link(p.join(temp.path, 'via-link'))..createSync(root);
    final linkedTop = p.join(link.path, 'rtl', 'top.sv');
    final paths = YosysSpanPathResolver(_request(link.path, [linkedTop]));
    expect(paths.resolve(p.join('rtl', 'top.sv')), linkedTop);
    // Relative from the real directory to the linked spelling of the file.
    expect(
      paths.resolve(p.join('..', 'via-link', 'rtl', 'top.sv')),
      linkedTop,
    );
  }, skip: Platform.isWindows ? 'directory links need privileges' : false);

  test('with no project root, the first source directory anchors it', () {
    final paths = YosysSpanPathResolver(_request('', [top]));
    expect(paths.resolve('top.sv'), top);
  });
}
