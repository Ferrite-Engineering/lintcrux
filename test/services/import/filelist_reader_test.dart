// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/import/filelist_reader.dart';
import 'package:path/path.dart' as p;

/// Mirrors `FilelistReader._resolvePath` so expectations match production
/// output on every platform: absolute Unix paths in these fixtures (e.g.
/// `/rtl/home/top.sv`) are absolute on POSIX but root-relative under Windows
/// path semantics, so the reader normalizes them differently per-OS. Building
/// the expected values through the same rule keeps the assertions OS-agnostic.
List<String> _resolved(List<String> raw, String baseDir) => [
  for (final path in raw)
    if (p.isAbsolute(path))
      p.normalize(path)
    else
      p.normalize(p.join(baseDir, path)),
];

void main() {
  group('FilelistReader', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('filelist-reader-');
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('parses a flat filelist with comments and bare sources', () {
      final f = File(p.join(dir.path, 'rtl.f'))
        ..writeAsStringSync('''
// Top-level RTL for the design under test
top.sv
core/alu.sv
core/regfile.v
# trailing-style comment
''');
      const reader = FilelistReader();
      final out = reader.read(f.path);
      expect(out.sourceFiles, [
        p.normalize(p.join(dir.path, 'top.sv')),
        p.normalize(p.join(dir.path, 'core/alu.sv')),
        p.normalize(p.join(dir.path, 'core/regfile.v')),
      ]);
      expect(out.includePaths, isEmpty);
      expect(out.defines, isEmpty);
    });

    test('parses +incdir+ and +define+ tokens', () {
      final f = File(p.join(dir.path, 'rtl.f'))
        ..writeAsStringSync('''
+incdir+include
+define+WIDTH=8
+define+DEBUG
top.sv
''');
      const reader = FilelistReader();
      final out = reader.read(f.path);
      expect(
        out.includePaths,
        [p.normalize(p.join(dir.path, 'include'))],
      );
      expect(out.defines, {'WIDTH': '8', 'DEBUG': ''});
      expect(out.sourceFiles, [p.normalize(p.join(dir.path, 'top.sv'))]);
    });

    test('parses multi-clause +incdir+ and +define+ tokens', () {
      final f = File(p.join(dir.path, 'rtl.f'))
        ..writeAsStringSync('+incdir+/a+/b+/c\n+define+X=1+Y=2\n');
      const reader = FilelistReader();
      final out = reader.read(f.path);
      expect(out.includePaths, _resolved(['/a', '/b', '/c'], dir.path));
      expect(out.defines, {'X': '1', 'Y': '2'});
    });

    test('recursive -f include is inlined at the current position', () {
      File(
        p.join(dir.path, 'inner.f'),
      ).writeAsStringSync('+incdir+inc_inner\nfile_inner.sv\n');
      File(p.join(dir.path, 'outer.f')).writeAsStringSync('''
file_outer1.sv
-f inner.f
file_outer2.sv
''');
      const reader = FilelistReader();
      final out = reader.read(p.join(dir.path, 'outer.f'));
      expect(out.sourceFiles, [
        p.normalize(p.join(dir.path, 'file_outer1.sv')),
        p.normalize(p.join(dir.path, 'file_inner.sv')),
        p.normalize(p.join(dir.path, 'file_outer2.sv')),
      ]);
      expect(
        out.includePaths,
        [p.normalize(p.join(dir.path, 'inc_inner'))],
      );
    });

    test('cycle in recursive includes raises a clear exception', () {
      File(p.join(dir.path, 'a.f')).writeAsStringSync('-f b.f\n');
      File(p.join(dir.path, 'b.f')).writeAsStringSync('-f a.f\n');
      const reader = FilelistReader();
      expect(
        () => reader.read(p.join(dir.path, 'a.f')),
        throwsA(
          isA<FilelistImportException>().having(
            (e) => e.message,
            'message',
            contains('cycle'),
          ),
        ),
      );
    });

    test('environment-variable expansion in source paths', () {
      File(p.join(dir.path, 'env.f')).writeAsStringSync(
        r'$RTL_HOME/top.sv'
        '\n',
      );
      const reader = FilelistReader(
        environment: {
          'RTL_HOME': '/rtl/home',
        },
      );
      final out = reader.read(p.join(dir.path, 'env.f'));
      expect(out.sourceFiles, _resolved(['/rtl/home/top.sv'], dir.path));
    });

    test('environment-variable expansion with braces', () {
      File(p.join(dir.path, 'env.f')).writeAsStringSync(
        r'${RTL_HOME}/top.sv'
        '\n',
      );
      const reader = FilelistReader(
        environment: {
          'RTL_HOME': '/rtl/home',
        },
      );
      final out = reader.read(p.join(dir.path, 'env.f'));
      expect(out.sourceFiles, _resolved(['/rtl/home/top.sv'], dir.path));
    });

    test(
      'undefined env variables expand to empty string (Verilator-style)',
      () {
        File(p.join(dir.path, 'env.f')).writeAsStringSync(
          r'$UNDEFINED/top.sv'
          '\n',
        );
        const reader = FilelistReader(environment: {});
        final out = reader.read(p.join(dir.path, 'env.f'));
        // $UNDEFINED → '' → '/top.sv'
        expect(out.sourceFiles, _resolved(['/top.sv'], dir.path));
      },
    );

    test('inline-style trailing comments are stripped', () {
      File(
        p.join(dir.path, 'rtl.f'),
      ).writeAsStringSync('top.sv  // primary RTL\n');
      const reader = FilelistReader();
      final out = reader.read(p.join(dir.path, 'rtl.f'));
      expect(out.sourceFiles, [p.normalize(p.join(dir.path, 'top.sv'))]);
    });

    test('unknown -X / +X tokens are silently dropped', () {
      File(p.join(dir.path, 'rtl.f')).writeAsStringSync('''
-some-tool-flag
+verilator-specific
top.sv
''');
      const reader = FilelistReader();
      final out = reader.read(p.join(dir.path, 'rtl.f'));
      expect(out.sourceFiles, [p.normalize(p.join(dir.path, 'top.sv'))]);
    });

    test('missing file argument to -f raises', () {
      File(p.join(dir.path, 'rtl.f')).writeAsStringSync('-f\n');
      const reader = FilelistReader();
      expect(
        () => reader.read(p.join(dir.path, 'rtl.f')),
        throwsA(isA<FilelistImportException>()),
      );
    });

    test('reading a non-existent filelist raises', () {
      const reader = FilelistReader();
      expect(
        () => reader.read(p.join(dir.path, 'nope.f')),
        throwsA(isA<FilelistImportException>()),
      );
    });

    test(
      'absolute source paths are preserved unchanged (modulo normalize)',
      () {
        File(
          p.join(dir.path, 'rtl.f'),
        ).writeAsStringSync('/abs/path/to/top.sv\n');
        const reader = FilelistReader();
        final out = reader.read(p.join(dir.path, 'rtl.f'));
        expect(out.sourceFiles, _resolved(['/abs/path/to/top.sv'], dir.path));
      },
    );
  });
}
