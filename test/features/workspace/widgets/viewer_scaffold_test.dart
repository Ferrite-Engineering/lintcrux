// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/project/providers/project_picker_provider.dart';
import 'package:lintcrux/features/project/services/project_picker.dart';
import 'package:lintcrux/features/workspace/providers/recent_projects_provider.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/features/workspace/widgets/empty_canvas_content.dart';
import 'package:lintcrux/features/workspace/widgets/lintcrux_toolbar.dart';
import 'package:lintcrux/features/workspace/widgets/viewer_scaffold.dart';
import 'package:lintcrux/features/workspace/widgets/workspace_root.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';
import 'package:lintcrux/services/workspace/lintcrux_workspace_codec.dart';
import 'package:path/path.dart' as p;
import '../../../support/telemetry_test_store.dart';

/// Test double for [ProjectPicker]. Each `pick*` method returns the
/// canned result configured for that flow, or throws [throwError] when
/// set (simulating the OS file dialog raising, e.g. a plugin failure).
class _FakeProjectPicker extends ProjectPicker {
  _FakeProjectPicker({
    this.projectFileResult,
    this.sessionFileResult,
    this.workspaceFileResult,
    this.saveProjectFileResult,
    this.throwError,
  });

  final String? projectFileResult;
  final String? sessionFileResult;
  final String? workspaceFileResult;
  final String? saveProjectFileResult;
  final Exception? throwError;

  @override
  Future<String?> pickProjectFile({
    required String confirmButtonText,
    required String typeLabel,
  }) async {
    final err = throwError;
    if (err != null) throw err;
    return projectFileResult;
  }

  @override
  Future<String?> pickSessionFile({
    required String confirmButtonText,
    required String typeLabel,
  }) async {
    final err = throwError;
    if (err != null) throw err;
    return sessionFileResult;
  }

  @override
  Future<String?> pickWorkspaceFile({
    required String confirmButtonText,
    required String typeLabel,
  }) async {
    final err = throwError;
    if (err != null) throw err;
    return workspaceFileResult;
  }

  @override
  Future<String?> pickSaveProjectFile({
    required String confirmButtonText,
    required String typeLabel,
    String? defaultFileName,
  }) async {
    final err = throwError;
    if (err != null) throw err;
    return saveProjectFileResult;
  }
}

/// `WorkspaceService` double whose `loadFromPath` raises unconditionally
/// so `_handleOpenWorkspace`'s failure snackbar branch (which the real
/// service otherwise never triggers — see
/// `open_project_in_workspace_test.dart`) is reachable from a widget test.
class _ThrowingLoadWorkspaceService extends WorkspaceService {
  _ThrowingLoadWorkspaceService({required super.directoryFactory})
    : super(codec: const LintcruxWorkspaceCodec());

  @override
  Future<Workspace> loadFromPath(String path) {
    throw Exception('simulated workspace load failure');
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    // The IDE layout rendered for an opened tab needs a desktop-sized
    // surface to avoid RenderFlex overflow (see project_tab_content_test).
    binding.platformDispatcher.views.first.physicalSize = const Size(
      1600,
      1000,
    );
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
    tempDir = await Directory.systemTemp.createTemp('lintcrux_vs_test_');
  });

  tearDown(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  WorkspaceService buildWorkspaceService() {
    return WorkspaceService(
      codec: const LintcruxWorkspaceCodec(),
      directoryFactory: () async => tempDir,
    );
  }

  Future<String> writeProjectFile(String name, {String? rootPath}) async {
    final path = p.join(tempDir.path, '$name.lintcrux');
    await File(path).writeAsString(
      jsonEncode({
        'version': 1,
        'name': name,
        'rootPath': rootPath ?? tempDir.path,
        'enabledEngineIds': <String>[],
      }),
    );
    return path;
  }

  Widget harness({
    required ProjectPicker picker,
    WorkspaceService? workspaceService,
    List<String> recentProjects = const <String>[],
    Locale locale = const Locale('en'),
  }) {
    return ProviderScope(
      overrides: [
        ...telemetryDeclinedOverrides(),
        workspaceServiceProvider.overrideWithValue(
          workspaceService ?? buildWorkspaceService(),
        ),
        engineRegistryProvider.overrideWithValue(EngineRegistry(const [])),
        projectPickerProvider.overrideWithValue(picker),
        recentProjectsProvider.overrideWithValue(recentProjects),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          L10N.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10N.supportedLocales,
        home: const WorkspaceRoot(child: ViewerScaffold()),
      ),
    );
  }

  // These tests only assert that the handler opened a tab, not that the
  // full four-pane IDE layout (`ProjectTabContent`) itself finished
  // settling, so a small bounded pump sequence stands in for
  // `pumpAndSettle()` after any action that opens a tab — cheaper, and
  // it does not depend on the IDE layout's own animations quiescing.
  Future<void> pumpBounded(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // The handlers under test do real disk I/O (`ProjectFileService`,
  // `OpenProjectInWorkspace`) as a fire-and-forget continuation of the
  // tap, not something the test itself awaits. That real I/O runs on
  // whatever zone the tap was dispatched from, so it only actually
  // resolves if the tap (and the real-time waiting after it) runs inside
  // `tester.runAsync` — a `tester.pump()` afterward only drains work
  // already delivered to the fake-clock test binding, it does not force
  // pending real I/O to complete first.
  //
  // A single fixed `Future.delayed` after the tap raced that real I/O:
  // under load the continuation had not resolved when the delay elapsed,
  // so the assertions saw the pre-I/O state and the suite went red
  // intermittently. Instead we poll [until] — advancing real time in
  // small steps inside `runAsync`, then pumping OUTSIDE it (pump asserts
  // when called from within a `runAsync` callback) so the widget tree
  // rebuilds and finders re-evaluate — until the caller's condition holds
  // or [timeout] elapses. The condition is left unmet on timeout so the
  // caller's own `expect` produces the failure with full context.
  Future<void> tapAndAwaitRealWork(
    WidgetTester tester,
    Finder finder, {
    required bool Function() until,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    await tester.runAsync(() => tester.tap(finder));
    final deadline = DateTime.now().add(timeout);
    while (!until()) {
      if (DateTime.now().isAfter(deadline)) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await pumpBounded(tester);
  }

  L10N l10nOf(WidgetTester tester) =>
      L10N.of(tester.element(find.byType(ViewerScaffold)));

  ProviderContainer rootContainerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(ViewerScaffold)),
        listen: false,
      );

  group('ViewerScaffold — empty canvas', () {
    testWidgets('renders the toolbar and empty-canvas actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(picker: _FakeProjectPicker()),
      );
      await tester.pumpAndSettle();

      final l10n = l10nOf(tester);
      // VS Code-style chrome: the tier-1 toolbar sits below the window title
      // bar as a plain strip (no Material AppBar / in-window app-title band).
      expect(find.byType(LintcruxToolbar), findsOneWidget);
      expect(find.byType(EmptyCanvasContent), findsOneWidget);
      expect(find.text(l10n.emptyCanvasOpenProjectButton), findsOneWidget);
      expect(find.text(l10n.emptyCanvasOpenWorkspaceButton), findsOneWidget);
      expect(find.text(l10n.emptyCanvasOpenSessionButton), findsOneWidget);
      expect(find.text(l10n.emptyCanvasNewProjectButton), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ViewerScaffold — Open Project', () {
    testWidgets(
      'tapping Open Project with a valid picked path opens the project '
      'into a new workspace tab',
      (tester) async {
        final path = (await tester.runAsync(() => writeProjectFile('demo')))!;
        await tester.pumpWidget(
          harness(picker: _FakeProjectPicker(projectFileResult: path)),
        );
        await tester.pumpAndSettle();

        final l10n = l10nOf(tester);
        await tapAndAwaitRealWork(
          tester,
          find.text(l10n.emptyCanvasOpenProjectButton),
          until: () => find.byType(EmptyCanvasContent).evaluate().isEmpty,
        );

        expect(find.byType(EmptyCanvasContent), findsNothing);
        final workspace = rootContainerOf(
          tester,
        ).read(workspaceProvider).requireValue;
        expect(workspace.tabs, hasLength(1));
        expect(find.text('demo'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'tapping Open Project when the user cancels the picker (null path) '
      'is a no-op — no tab opens and no snackbar appears',
      (tester) async {
        await tester.pumpWidget(
          harness(picker: _FakeProjectPicker()),
        );
        await tester.pumpAndSettle();

        final l10n = l10nOf(tester);
        await tester.tap(find.text(l10n.emptyCanvasOpenProjectButton));
        await tester.pumpAndSettle();

        expect(find.byType(EmptyCanvasContent), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
        final workspace = rootContainerOf(
          tester,
        ).read(workspaceProvider).requireValue;
        expect(workspace.tabs, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'tapping Open Project when the picker throws surfaces a '
      'filePickerFailed snackbar with the error text',
      (tester) async {
        await tester.pumpWidget(
          harness(
            picker: _FakeProjectPicker(
              throwError: Exception('picker unavailable'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final l10n = l10nOf(tester);
        await tapAndAwaitRealWork(
          tester,
          find.text(l10n.emptyCanvasOpenProjectButton),
          until: () => find
              .text(l10n.filePickerFailed('Exception: picker unavailable'))
              .evaluate()
              .isNotEmpty,
        );

        expect(
          find.text(
            l10n.filePickerFailed('Exception: picker unavailable'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'tapping Open Project with a path that fails to load surfaces a '
      "snackbar with the opener's failure message",
      (tester) async {
        final badPath = p.join(tempDir.path, 'broken.lintcrux');
        await tester.runAsync(
          () => File(badPath).writeAsString('not valid json'),
        );
        await tester.pumpWidget(
          harness(picker: _FakeProjectPicker(projectFileResult: badPath)),
        );
        await tester.pumpAndSettle();

        final l10n = l10nOf(tester);
        await tapAndAwaitRealWork(
          tester,
          find.text(l10n.emptyCanvasOpenProjectButton),
          until: () =>
              find.textContaining('invalid JSON').evaluate().isNotEmpty,
        );

        expect(find.textContaining('invalid JSON'), findsOneWidget);
        final workspace = rootContainerOf(
          tester,
        ).read(workspaceProvider).requireValue;
        expect(workspace.tabs, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('ViewerScaffold — Open Session', () {
    testWidgets(
      'tapping Open Session with a path to a missing session file '
      'surfaces a failure snackbar',
      (tester) async {
        final missingSessionPath = p.join(
          tempDir.path,
          'gone.lintcrux-session',
        );
        await tester.pumpWidget(
          harness(
            picker: _FakeProjectPicker(
              sessionFileResult: missingSessionPath,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final l10n = l10nOf(tester);
        await tapAndAwaitRealWork(
          tester,
          find.text(l10n.emptyCanvasOpenSessionButton),
          until: () => find
              .text(
                'LintcruxSessionLoadException: Session file does not exist.',
              )
              .evaluate()
              .isNotEmpty,
        );

        expect(
          find.text(
            'LintcruxSessionLoadException: Session file does not exist.',
          ),
          findsOneWidget,
        );
        final workspace = rootContainerOf(
          tester,
        ).read(workspaceProvider).requireValue;
        expect(workspace.tabs, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('ViewerScaffold — Open Workspace', () {
    testWidgets(
      'tapping Open Workspace when the workspace service raises surfaces '
      'a workspaceLoadFailed snackbar carrying the error text',
      (tester) async {
        final throwingService = _ThrowingLoadWorkspaceService(
          directoryFactory: () async => tempDir,
        );
        await tester.pumpWidget(
          harness(
            picker: _FakeProjectPicker(
              workspaceFileResult: p.join(
                tempDir.path,
                'irrelevant.lintcrux-workspace',
              ),
            ),
            workspaceService: throwingService,
          ),
        );
        await tester.pumpAndSettle();

        final l10n = l10nOf(tester);
        await tapAndAwaitRealWork(
          tester,
          find.text(l10n.emptyCanvasOpenWorkspaceButton),
          until: () => find
              .text(
                l10n.workspaceLoadFailed(
                  'Exception: simulated workspace load failure',
                ),
              )
              .evaluate()
              .isNotEmpty,
        );

        expect(
          find.text(
            l10n.workspaceLoadFailed(
              'Exception: simulated workspace load failure',
            ),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('ViewerScaffold — New Project', () {
    testWidgets(
      'tapping New Project with a valid save path writes the project '
      'file to disk and opens it into a new tab',
      (tester) async {
        final savePath = p.join(tempDir.path, 'fresh_project');
        await tester.pumpWidget(
          harness(
            picker: _FakeProjectPicker(saveProjectFileResult: savePath),
          ),
        );
        await tester.pumpAndSettle();

        final l10n = l10nOf(tester);
        await tapAndAwaitRealWork(
          tester,
          find.text(l10n.emptyCanvasNewProjectButton),
          until: () => find.byType(EmptyCanvasContent).evaluate().isEmpty,
        );

        final writtenFile = File('$savePath.lintcrux');
        expect(writtenFile.existsSync(), isTrue);
        final workspace = rootContainerOf(
          tester,
        ).read(workspaceProvider).requireValue;
        expect(workspace.tabs, hasLength(1));
        expect(find.byType(EmptyCanvasContent), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'tapping New Project with a save path in a non-existent directory '
      'surfaces a write-failure snackbar instead of throwing',
      (tester) async {
        final savePath = p.join(tempDir.path, 'missing_subdir', 'project');
        await tester.pumpWidget(
          harness(
            picker: _FakeProjectPicker(saveProjectFileResult: savePath),
          ),
        );
        await tester.pumpAndSettle();

        final l10n = l10nOf(tester);
        await tapAndAwaitRealWork(
          tester,
          find.text(l10n.emptyCanvasNewProjectButton),
          until: () => find
              .textContaining('could not write project file')
              .evaluate()
              .isNotEmpty,
        );

        expect(
          File('$savePath.lintcrux').existsSync(),
          isFalse,
        );
        expect(
          find.textContaining('could not write project file'),
          findsOneWidget,
        );
        final workspace = rootContainerOf(
          tester,
        ).read(workspaceProvider).requireValue;
        expect(workspace.tabs, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('ViewerScaffold — Open Recent Project', () {
    testWidgets(
      'tapping a recent-project row opens it into a new tab',
      (tester) async {
        final path = (await tester.runAsync(
          () => writeProjectFile('recent_demo'),
        ))!;
        await tester.pumpWidget(
          harness(
            picker: _FakeProjectPicker(),
            recentProjects: [path],
          ),
        );
        await tester.pumpAndSettle();

        await tapAndAwaitRealWork(
          tester,
          find.text(path),
          until: () => find.byType(EmptyCanvasContent).evaluate().isEmpty,
        );

        final workspace = rootContainerOf(
          tester,
        ).read(workspaceProvider).requireValue;
        expect(workspace.tabs, hasLength(1));
        expect(find.byType(EmptyCanvasContent), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'tapping a recent-project row whose file no longer exists surfaces '
      'a failure snackbar and leaves the workspace empty',
      (tester) async {
        final missingPath = p.join(tempDir.path, 'vanished.lintcrux');
        await tester.pumpWidget(
          harness(
            picker: _FakeProjectPicker(),
            recentProjects: [missingPath],
          ),
        );
        await tester.pumpAndSettle();

        await tapAndAwaitRealWork(
          tester,
          find.text(missingPath),
          until: () => find
              .textContaining('could not read project file')
              .evaluate()
              .isNotEmpty,
        );

        expect(
          find.textContaining('could not read project file'),
          findsOneWidget,
        );
        final workspace = rootContainerOf(
          tester,
        ).read(workspaceProvider).requireValue;
        expect(workspace.tabs, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('ViewerScaffold — locale sweep', () {
    testWidgets(
      'renders the empty-canvas shell without exceptions in every '
      'supported locale',
      (tester) async {
        for (final locale in L10N.supportedLocales) {
          await tester.pumpWidget(
            harness(picker: _FakeProjectPicker(), locale: locale),
          );
          await tester.pumpAndSettle();
          final l10n = l10nOf(tester);
          expect(
            find.text(l10n.emptyCanvasOpenProjectButton),
            findsOneWidget,
            reason: 'Open Project button missing for $locale',
          );
          expect(tester.takeException(), isNull, reason: 'failed for $locale');
        }
      },
    );
  });
}
