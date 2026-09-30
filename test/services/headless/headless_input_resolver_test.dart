// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/services/headless/headless_input_resolver.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lintcrux_input_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  File writeFile(String relative, String contents) {
    final f = File(p.join(tmp.path, relative));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(contents);
    return f;
  }

  const resolver = HeadlessInputResolver();

  group('HeadlessInputResolver — unusable positionals are reported', () {
    // This whole group exists because the pre-headless behavior was to
    // silently drop anything that was not a `.lintcrux`, which turned a
    // typo into a green build over zero files.

    test('no arguments at all is an error, not an empty clean run', () async {
      final r = await resolver.resolve(const <String>[]);
      expect(r.isSuccess, isFalse);
      expect(r.problems.single, contains('No input'));
    });

    test('a positional with an unknown extension is reported', () async {
      final r = await resolver.resolve(const <String>['notes.txt']);
      expect(r.isSuccess, isFalse);
      expect(r.problems.single, contains('notes.txt'));
      expect(r.problems.single, contains('lintable HDL extension'));
    });

    test('every unusable positional is reported, not just the first', () async {
      final r = await resolver.resolve(const <String>['a.txt', 'b.md']);
      expect(r.problems, hasLength(2));
      expect(r.problems.join(), contains('a.txt'));
      expect(r.problems.join(), contains('b.md'));
    });

    test('a directory positional says so specifically', () async {
      final dir = Directory(p.join(tmp.path, 'rtl'))..createSync();
      final r = await resolver.resolve(<String>[dir.path]);
      expect(r.isSuccess, isFalse);
      expect(r.problems.single, contains('is a directory'));
    });

    test('mixing a project with loose sources is refused', () async {
      writeFile('top.sv', 'module top; endmodule');
      writeFile('p.lintcrux', '{"version":1,"name":"p","rootPath":"."}');
      final r = await resolver.resolve(<String>[
        p.join(tmp.path, 'p.lintcrux'),
        p.join(tmp.path, 'top.sv'),
      ]);
      expect(r.isSuccess, isFalse);
      expect(r.problems.join(), contains('Cannot mix'));
    });

    test('two project files are refused', () async {
      writeFile('a.lintcrux', '{"version":1,"name":"a","rootPath":"."}');
      writeFile('b.lintcrux', '{"version":1,"name":"b","rootPath":"."}');
      final r = await resolver.resolve(<String>[
        p.join(tmp.path, 'a.lintcrux'),
        p.join(tmp.path, 'b.lintcrux'),
      ]);
      expect(r.isSuccess, isFalse);
      expect(r.problems.join(), contains('at most one'));
    });

    test('a missing source file is reported', () async {
      final r = await resolver.resolve(<String>[p.join(tmp.path, 'gone.sv')]);
      expect(r.isSuccess, isFalse);
      expect(r.problems.single, contains('Source file not found'));
      expect(r.kind, HeadlessInputFailureKind.usage);
    });

    test('a missing project file is reported', () async {
      final r = await resolver.resolve(<String>[
        p.join(tmp.path, 'gone.lintcrux'),
      ]);
      expect(r.isSuccess, isFalse);
      expect(r.problems.single, contains('Project file not found'));
      expect(r.kind, HeadlessInputFailureKind.usage);
    });
  });

  group('HeadlessInputResolver — project mode', () {
    test('resolves sources against the project file directory', () async {
      writeFile('proj/rtl/top.sv', 'module top; endmodule');
      writeFile('proj/rtl/other.sv', 'module other; endmodule');
      final projectFile = writeFile('proj/design.lintcrux', '''
{
  "version": 1,
  "name": "design",
  "rootPath": "some/committed/relative/path",
  "sourceFiles": ["rtl/top.sv", "rtl/other.sv"],
  "includePaths": ["rtl"]
}
''');

      final r = await resolver.resolve(<String>[projectFile.path]);
      expect(r.isSuccess, isTrue, reason: r.problems.join('\n'));
      final project = r.project!;
      expect(project.sourceFiles, [
        p.join(tmp.path, 'proj', 'rtl', 'top.sv'),
        p.join(tmp.path, 'proj', 'rtl', 'other.sv'),
      ]);
      expect(project.includePaths.single, p.join(tmp.path, 'proj', 'rtl'));
    });

    test(
      'a RELATIVE rootPath is replaced by the project file directory',
      () async {
        // Committed `.lintcrux` files in this repo carry a rootPath that
        // is relative to the *repository* root and names the project's
        // own directory. Joining that against the project file's
        // directory doubles the path, which silently defeats SARIF
        // relativization: every artifactLocation.uri stays absolute and
        // GitHub code scanning annotates nothing. Found by running the
        // compiled binary, so it stays covered here.
        writeFile('proj/top.sv', 'module top; endmodule');
        final projectFile = writeFile('proj/design.lintcrux', '''
{
  "version": 1,
  "name": "design",
  "rootPath": "test/fixtures/projects/design",
  "sourceFiles": ["top.sv"]
}
''');
        final r = await resolver.resolve(<String>[projectFile.path]);
        expect(r.isSuccess, isTrue);
        expect(r.project!.rootPath, p.join(tmp.path, 'proj'));
        expect(
          r.project!.rootPath,
          isNot(contains('test/fixtures')),
          reason: 'the relative rootPath must not be joined onto the dir',
        );
      },
    );

    test('an ABSOLUTE rootPath is honored as written', () async {
      final root = Directory(p.join(tmp.path, 'elsewhere'))
        ..createSync(recursive: true);
      writeFile('proj/top.sv', 'module top; endmodule');
      final projectFile = writeFile('proj/design.lintcrux', '''
{
  "version": 1,
  "name": "design",
  "rootPath": ${_json(root.path)},
  "sourceFiles": ["top.sv"]
}
''');
      final r = await resolver.resolve(<String>[projectFile.path]);
      expect(r.isSuccess, isTrue);
      expect(r.project!.rootPath, root.path);
    });

    test('--top overrides the project topModule', () async {
      writeFile('proj/top.sv', 'module top; endmodule');
      final projectFile = writeFile('proj/design.lintcrux', '''
{
  "version": 1,
  "name": "design",
  "rootPath": ".",
  "sourceFiles": ["top.sv"],
  "topModule": "committed_top"
}
''');
      final overridden = await resolver.resolve(<String>[
        projectFile.path,
      ], topModule: 'ci_top');
      expect(overridden.project!.topModule, 'ci_top');

      final untouched = await resolver.resolve(<String>[projectFile.path]);
      expect(untouched.project!.topModule, 'committed_top');
    });

    test('a source file listed but absent from disk fails the run', () async {
      final projectFile = writeFile('proj/design.lintcrux', '''
{
  "version": 1,
  "name": "design",
  "rootPath": ".",
  "sourceFiles": ["missing.sv"]
}
''');
      final r = await resolver.resolve(<String>[projectFile.path]);
      expect(r.isSuccess, isFalse);
      expect(r.problems.single, contains('missing.sv'));
      expect(r.kind, HeadlessInputFailureKind.loadFailed);
    });

    test('a project with no source files fails rather than passing', () async {
      final projectFile = writeFile(
        'proj/design.lintcrux',
        '{"version":1,"name":"design","rootPath":".","sourceFiles":[]}',
      );
      final r = await resolver.resolve(<String>[projectFile.path]);
      expect(r.isSuccess, isFalse);
      expect(r.problems.single, contains('no source files'));
      expect(r.kind, HeadlessInputFailureKind.loadFailed);
    });

    test('an unparseable project file is a load failure', () async {
      final projectFile = writeFile('proj/design.lintcrux', '{ not json');
      final r = await resolver.resolve(<String>[projectFile.path]);
      expect(r.isSuccess, isFalse);
      expect(r.kind, HeadlessInputFailureKind.loadFailed);
    });
  });

  group('HeadlessInputResolver — ad-hoc mode', () {
    test('builds a project rooted at the common ancestor', () async {
      writeFile('rtl/a/top.sv', 'module top; endmodule');
      writeFile('rtl/b/other.sv', 'module other; endmodule');
      final r = await resolver.resolve(<String>[
        p.join(tmp.path, 'rtl', 'a', 'top.sv'),
        p.join(tmp.path, 'rtl', 'b', 'other.sv'),
      ], topModule: 'top');
      expect(r.isSuccess, isTrue, reason: r.problems.join('\n'));
      expect(r.project!.rootPath, p.join(tmp.path, 'rtl'));
      expect(r.project!.topModule, 'top');
      expect(r.project!.name, 'top');
      expect(r.projectFilePath, isNull);
    });

    test('infers systemVerilog for .sv / .v sources', () async {
      writeFile('a.v', '');
      final r = await resolver.resolve(<String>[p.join(tmp.path, 'a.v')]);
      expect(r.project!.language, HdlLanguage.systemVerilog);
    });

    test('infers vhdl for .vhd sources', () async {
      writeFile('a.vhd', '');
      final r = await resolver.resolve(<String>[p.join(tmp.path, 'a.vhd')]);
      expect(r.project!.language, HdlLanguage.vhdl);
    });

    test('infers mixed when both families are present', () async {
      writeFile('a.vhd', '');
      writeFile('b.sv', '');
      final r = await resolver.resolve(<String>[
        p.join(tmp.path, 'a.vhd'),
        p.join(tmp.path, 'b.sv'),
      ]);
      expect(r.project!.language, HdlLanguage.mixed);
    });

    test('accepts every documented source extension', () async {
      for (final ext in HeadlessInputResolver.sourceExtensions) {
        writeFile('src$ext', '');
        final r = await resolver.resolve(<String>[
          p.join(tmp.path, 'src$ext'),
        ]);
        expect(r.isSuccess, isTrue, reason: 'extension $ext should resolve');
      }
    });
  });
}

String _json(String s) =>
    '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
