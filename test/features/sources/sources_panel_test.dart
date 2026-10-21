// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/features/run/providers/lint_run_notifier.dart';
import 'package:lintcrux/features/sources/widgets/sources_panel.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/project/project_file_service.dart';
import 'package:lintcrux/services/project/project_path_resolver.dart';
import 'package:lintcrux/services/telemetry/telemetry_event_catalog.dart';
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

/// Records the runs a removal asks for instead of starting engines.
class _RecordingRun extends LintRunNotifier {
  final List<LintProject> runs = <LintProject>[];

  @override
  LintRunState build() => LintRunState.idle;

  @override
  Future<void> runAll(
    LintProject project, {
    bool forceBypassCache = false,
    LintRunTrigger trigger = LintRunTrigger.manual,
  }) async {
    runs.add(project);
  }
}

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

  testWidgets('lists pin-constraint files in their own section', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(currentProjectProvider.notifier)
        .load(
          const LintProject(
            name: 'board',
            rootPath: '/w/board',
            sourceFiles: <String>['/w/board/rtl/top.v'],
            constraintFiles: <String>[
              '/w/board/pins.pcf',
              '/w/board/alt/pins.cst',
            ],
          ),
        );
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    expect(find.text('1 source file'), findsOneWidget);
    expect(find.text('2 constraint files'), findsOneWidget);
    expect(find.text('top.v'), findsOneWidget);
    expect(find.text('pins.pcf'), findsOneWidget);
    expect(find.text('pins.cst'), findsOneWidget);
    // One remove button per row, constraint files included.
    expect(find.byIcon(Icons.close), findsNWidgets(3));
  });

  testWidgets('a project with only constraint files is not shown as empty', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(currentProjectProvider.notifier)
        .load(
          const LintProject(
            name: 'board',
            rootPath: '/w/board',
            constraintFiles: <String>['/w/board/pins.lpf'],
          ),
        );
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();
    expect(find.text('pins.lpf'), findsOneWidget);
    expect(find.textContaining('No source files'), findsNothing);
  });

  testWidgets(
    'removing a constraint file rewrites the project file, keeps paths '
    'relative, and leaves the sources alone',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('sources_panel_c');
      addTearDown(() => dir.deleteSync(recursive: true));
      final projectPath = p.join(dir.path, 'board.lintcrux');
      const service = ProjectFileService();
      const authored = LintProject(
        name: 'board',
        rootPath: '.',
        sourceFiles: <String>['rtl/top.v'],
        constraintFiles: <String>['pins.pcf', 'alt/pins.cst'],
      );
      await tester.runAsync(() => service.write(projectPath, authored));

      final run = _RecordingRun();
      final container = ProviderContainer(
        overrides: [lintRunProvider.overrideWith(() => run)],
      );
      addTearDown(container.dispose);
      container
          .read(currentProjectProvider.notifier)
          .load(
            resolveProjectPaths(authored, dir.path),
            projectFilePath: projectPath,
          );
      await tester.pumpWidget(_host(container));
      await tester.pumpAndSettle();

      // Rows: top.v first, then pins.pcf, pins.cst.
      await tester.tap(find.byIcon(Icons.close).at(1));
      await tester.pumpAndSettle();
      expect(find.text('Remove constraint file?'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      // The removal reads and writes the project file: real I/O, which the
      // test clock does not advance.
      for (var i = 0; i < 100 && run.runs.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }

      final reread = await tester.runAsync(() => service.read(projectPath));
      expect(reread!.constraintFiles, <String>['alt/pins.cst']);
      expect(reread.sourceFiles, <String>['rtl/top.v']);
      expect(
        reread.constraintFiles.every(p.isRelative),
        isTrue,
        reason: 'a committed .lintcrux must stay portable',
      );
      expect(
        container.read(currentProjectProvider)!.constraintFiles,
        <String>[p.join(dir.path, 'alt', 'pins.cst')],
      );
      expect(run.runs, hasLength(1), reason: 'the findings are re-derived');
    },
  );

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
