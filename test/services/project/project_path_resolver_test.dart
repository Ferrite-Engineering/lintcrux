// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// A `.lintcrux` project is committed from one host and opened on another.
// Every case names its path style through `pathContext`, so both styles run
// on every host, not only on the weekly Windows job.

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/util/portable_path.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/project_source_file.dart';
import 'package:lintcrux/services/project/project_file_codec.dart';
import 'package:lintcrux/services/project/project_path_resolver.dart';
import 'package:path/path.dart' as p;

void main() {
  final windows = p.Context(style: p.Style.windows);
  final posix = p.posix;
  const winDir = r'C:\Users\Dev\Designs\CPU';
  const posixDir = '/home/dev/designs/cpu';

  LintProject projectWith({
    List<String> sources = const <String>[],
    List<String> includes = const <String>[],
    List<String> constraints = const <String>[],
    Map<String, ProjectSourceFileLanguage> languages =
        const <String, ProjectSourceFileLanguage>{},
  }) => LintProject(
    name: 'cpu',
    rootPath: '.',
    sourceFiles: sources,
    includePaths: includes,
    constraintFiles: constraints,
    sourceFileLanguages: languages,
  );

  group('resolveProjectPaths', () {
    test('a Windows-saved project opens its sources under POSIX rules', () {
      final resolved = resolveProjectPaths(
        projectWith(
          sources: <String>[r'rtl\top.sv', r'..\ip\fifo.sv'],
          includes: <String>[r'rtl\inc'],
          constraints: <String>[r'board\pins.pcf'],
          languages: <String, ProjectSourceFileLanguage>{
            r'rtl\top.sv': ProjectSourceFileLanguage.systemVerilog,
          },
        ),
        posixDir,
        pathContext: posix,
      );
      expect(resolved.sourceFiles, <String>[
        '$posixDir/rtl/top.sv',
        '/home/dev/designs/ip/fifo.sv',
      ]);
      expect(resolved.includePaths, <String>['$posixDir/rtl/inc']);
      expect(resolved.constraintFiles, <String>['$posixDir/board/pins.pcf']);
      expect(resolved.sourceFileLanguages.keys, <String>[
        '$posixDir/rtl/top.sv',
      ]);
    });

    test('a file written with / opens under both styles', () {
      final project = projectWith(
        sources: <String>['rtl/top.sv', '../ip/f.sv'],
      );
      expect(
        resolveProjectPaths(project, winDir, pathContext: windows).sourceFiles,
        <String>[
          r'C:\Users\Dev\Designs\CPU\rtl\top.sv',
          r'C:\Users\Dev\Designs\ip\f.sv',
        ],
      );
      expect(
        resolveProjectPaths(project, posixDir, pathContext: posix).sourceFiles,
        <String>['$posixDir/rtl/top.sv', '/home/dev/designs/ip/f.sv'],
      );
    });

    test('Windows-absolute entries keep their not-found handling', () {
      final resolved = resolveProjectPaths(
        projectWith(sources: <String>[r'C:\Shared\fifo.sv']),
        posixDir,
        pathContext: posix,
      );
      expect(resolved.sourceFiles, <String>['$posixDir/C:\\Shared\\fifo.sv']);
    });

    test('an absolute POSIX entry containing a backslash is untouched', () {
      final resolved = resolveProjectPaths(
        projectWith(sources: <String>[r'/opt/we\ird/f.sv']),
        posixDir,
        pathContext: posix,
      );
      expect(resolved.sourceFiles, <String>[r'/opt/we\ird/f.sv']);
    });

    test('a Windows project keeps the case of what its author wrote', () {
      final resolved = resolveProjectPaths(
        projectWith(sources: <String>[r'RTL\Top.sv']),
        winDir,
        pathContext: windows,
      );
      expect(resolved.sourceFiles, <String>[
        r'C:\Users\Dev\Designs\CPU\RTL\Top.sv',
      ]);
    });
  });

  group('writing then reading a project file', () {
    const codec = ProjectFileCodec();

    // MUTATION: writing `p.relative` unchanged (host separators) makes the
    // Windows case red.
    test('a file saved on Windows contains no backslash in its entries', () {
      final entry = portableProjectEntry(
        r'C:\Users\Dev\Designs\CPU\rtl\top.sv',
        winDir,
        context: windows,
      );
      final text = codec.encode(projectWith(sources: <String>[entry]));
      expect(text, contains('"rtl/top.sv"'));
      expect(text, isNot(contains(r'\\')));
    });

    test('Windows to POSIX round trip finds the same file', () {
      final entry = portableProjectEntry(
        r'C:\Users\Dev\Designs\CPU\rtl\top.sv',
        winDir,
        context: windows,
      );
      final committed = codec.decode(
        codec.encode(projectWith(sources: <String>[entry])),
      );
      final onPosix = resolveProjectPaths(
        committed,
        posixDir,
        pathContext: posix,
      );
      expect(onPosix.sourceFiles, <String>['$posixDir/rtl/top.sv']);
    });

    test('POSIX to Windows round trip finds the same file', () {
      final entry = portableProjectEntry(
        '$posixDir/rtl/top.sv',
        posixDir,
        context: posix,
      );
      final committed = codec.decode(
        codec.encode(projectWith(sources: <String>[entry])),
      );
      final onWindows = resolveProjectPaths(
        committed,
        winDir,
        pathContext: windows,
      );
      expect(onWindows.sourceFiles, <String>[
        r'C:\Users\Dev\Designs\CPU\rtl\top.sv',
      ]);
    });
  });
}
