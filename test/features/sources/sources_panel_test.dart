// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/features/sources/widgets/sources_panel.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/project/project_file_service.dart';
import 'package:path/path.dart' as p;

/// The sources panel, and the round trip that makes removal safe.
///
/// The panel exists because adding a source was a one-way door: the picker
/// appended to the project, nothing listed what a project contained, and a
/// wrong file could only be undone by hand-editing `.lintcrux`.
Widget _host(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: const MaterialApp(
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(body: SourcesPanel()),
  ),
);

void main() {
  testWidgets('with no project open it says so rather than looking empty', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();
    // "No project" and "project with no sources" are different situations and
    // an empty list would render identically for both.
    expect(find.textContaining('Open a project'), findsOneWidget);
  });

  testWidgets('lists every source, basename first', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(currentProjectProvider.notifier)
        .load(
          const LintProject(
            name: 'demo',
            rootPath: '/w/demo',
            sourceFiles: <String>['/w/demo/rtl/top.v', '/w/demo/rtl/fifo.v'],
          ),
        );
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    // Basename leads: a column of long absolute paths distinguishes nothing
    // at the point the eye lands, and the basename is what differs.
    expect(find.text('top.v'), findsOneWidget);
    expect(find.text('fifo.v'), findsOneWidget);
    expect(find.text('2 source files'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNWidgets(2));
  });

  test('removal rewrites the project file and keeps paths RELATIVE', () async {
    // The property that matters most and is easiest to get wrong. Adding
    // re-reads the authored (relative) form, edits it, and writes it back;
    // removal must do the same in reverse. Writing resolved absolute paths
    // would still work on this machine and break the moment the `.lintcrux`
    // is committed and opened by anyone else.
    final dir = await Directory.systemTemp.createTemp('sources_panel');
    addTearDown(() => dir.delete(recursive: true));
    final projectPath = p.join(dir.path, 'demo.lintcrux');
    const service = ProjectFileService();
    await service.write(
      projectPath,
      const LintProject(
        name: 'demo',
        rootPath: '.',
        sourceFiles: <String>['rtl/top.v', 'rtl/fifo.v'],
      ),
    );

    // Simulate what removeSourceFromProject writes: the authored form minus
    // the entry whose RESOLVED path matches the absolute one the panel shows.
    final authored = await service.read(projectPath);
    final target = p.join(dir.path, 'rtl', 'fifo.v');
    final remaining = <String>[
      for (final a in authored.sourceFiles)
        if (p.canonicalize(p.join(dir.path, a)) != p.canonicalize(target)) a,
    ];
    expect(
      remaining,
      <String>['rtl/top.v'],
      reason:
          'matching authored strings against an absolute path directly '
          'removes nothing — the comparison has to resolve first',
    );

    await service.write(
      projectPath,
      authored.copyWith(sourceFiles: remaining),
    );
    final reread = await service.read(projectPath);
    expect(reread.sourceFiles, <String>['rtl/top.v']);
    expect(
      reread.sourceFiles.every(p.isRelative),
      isTrue,
      reason: 'a committed .lintcrux must stay portable',
    );
  });
}
