// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/session/lintcrux_session.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';
import 'package:lintcrux/features/project/services/open_project_service.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/workspace/providers/recent_projects_provider.dart';
import 'package:lintcrux/features/workspace/providers/tab_overrides_factory.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/features/workspace/services/open_project_in_workspace.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/session/session_service.dart';
import 'package:lintcrux/services/workspace/lintcrux_workspace_codec.dart';
import 'package:path/path.dart' as p;

import '../../../support/fake_path_provider.dart';
import '../../../support/telemetry_test_store.dart';

/// Test double proving [OpenProjectInWorkspace.openWorkspace]'s outer
/// try/catch converts a raised [Exception] into an error-message
/// return rather than letting it propagate — the real
/// `WorkspaceService.loadFromPath` swallows every failure internally
/// (see the adjacent test), so this double is the only way to exercise
/// that branch.
class _ThrowingLoadWorkspaceService extends WorkspaceService {
  _ThrowingLoadWorkspaceService()
    : super(codec: const LintcruxWorkspaceCodec());

  @override
  Future<Workspace> loadFromPath(String path) {
    throw Exception('simulated load failure');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The `_ThrowingLoadWorkspaceService` branch builds a real
  // `WorkspaceService` without a `directoryFactory`, so its directory
  // resolution reaches `getApplicationSupportDirectory()`. Under
  // `flutter test` that throws `MissingPluginException` on macOS/Windows
  // (pure-Dart only on Linux). The fake makes resolution succeed on every
  // host instead of relying on the service's swallow-and-degrade fallback.
  useFakePathProvider();

  late Directory tempDir;
  late ProviderContainer root;
  final tabContainers = <crux.TabId, ProviderContainer>{};

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lintcrux_opw_test_');
    root = ProviderContainer(
      overrides: [
        ...telemetryDeclinedOverrides(),
        engineRegistryProvider.overrideWithValue(EngineRegistry(const [])),
        workspaceServiceProvider.overrideWithValue(
          WorkspaceService(
            codec: const LintcruxWorkspaceCodec(),
            directoryFactory: () async => tempDir,
          ),
        ),
      ],
    );
    tabContainers.clear();
  });

  tearDown(() async {
    for (final c in tabContainers.values) {
      c.dispose();
    }
    tabContainers.clear();
    root.dispose();
    if (tempDir.existsSync()) {
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        // Best-effort cleanup.
      }
    }
  });

  /// Mirrors `TabContainerManager`'s child-container construction: the
  /// per-tab open-core override list layered on a child of [root].
  ProviderContainer tabsForId(crux.TabId tabId) {
    return tabContainers.putIfAbsent(
      tabId,
      () => ProviderContainer(
        parent: root,
        overrides: lintcruxTabOverridesFactory(tabId),
      ),
    );
  }

  Future<String> writeProjectFile(String name) async {
    final path = p.join(tempDir.path, '$name.lintcrux');
    await File(path).writeAsString(
      jsonEncode({
        'version': 1,
        'name': name,
        'rootPath': tempDir.path,
        'enabledEngineIds': <String>[],
      }),
    );
    return path;
  }

  group('OpenProjectInWorkspace.openProject', () {
    test('loads the project into the NEW TAB container only — the root '
        'currentProjectProvider stays null', () async {
      final path = await writeProjectFile('demo');
      await root.read(workspaceProvider.future);
      final opener = root.read(openProjectInWorkspaceProvider)(tabsForId);

      final result = await opener.openProject(path);
      expect(result, isA<OpenProjectSuccess>());

      // The new tab's per-tab provider carries the project.
      final workspace = root.read(workspaceProvider).requireValue;
      expect(workspace.tabs, hasLength(1));
      final tab = tabsForId(workspace.tabs.single.id);
      expect(tab.read(currentProjectProvider)?.name, 'demo');

      // The ROOT container must NOT hold the project: the per-project
      // stores (waivers, baseline, bookmarks, cache, Verible) are
      // per-tab, and a root-scope project would let a root-resolved
      // store write into a directory no visible tab corresponds to.
      expect(root.read(currentProjectProvider), isNull);
    });

    test('an opened project is added to the Recent projects list', () async {
      final path = await writeProjectFile('recent');
      await root.read(workspaceProvider.future);
      final opener = root.read(openProjectInWorkspaceProvider)(tabsForId);
      await opener.openProject(path);
      expect(root.read(recentProjectsProvider).first, path);
    });

    test('the tab remembers the file it was opened from, so an edit made '
        'in Settings is saved to that file', () async {
      final path = await writeProjectFile('persisted');
      await root.read(workspaceProvider.future);
      final opener = root.read(openProjectInWorkspaceProvider)(tabsForId);
      await opener.openProject(path);

      final workspace = root.read(workspaceProvider).requireValue;
      final tab = tabsForId(workspace.tabs.single.id);
      final notifier = tab.read(currentProjectProvider.notifier);
      expect(notifier.projectFilePath, path);

      await notifier.saveSeverityOverride(
        'verilator/UNUSEDSIGNAL',
        Severity.note,
      );
      final onDisk = jsonDecode(File(path).readAsStringSync()) as Map;
      expect(onDisk['severityOverrides'], {'verilator/UNUSEDSIGNAL': 'note'});
    });

    // Tab dedupe (beta regression): the CLI positional-path flow calls straight
    // into this method, and every launch appended one more tab for the same
    // project.
    test('re-opening the same project focuses the existing tab', () async {
      final path = await writeProjectFile('riscv-soc');
      await root.read(workspaceProvider.future);
      final opener = root.read(openProjectInWorkspaceProvider)(tabsForId);

      final first = await opener.openProject(path);
      final second = await opener.openProject(path);

      expect(first, isA<OpenProjectSuccess>());
      expect(second, isA<OpenProjectSuccess>());
      expect((first as OpenProjectSuccess).deduped, isFalse);
      expect((second as OpenProjectSuccess).deduped, isTrue);
      expect(second.tabId, first.tabId);

      final workspace = root.read(workspaceProvider).requireValue;
      expect(workspace.tabs, hasLength(1));
      // The focused tab is the active one.
      expect(workspace.activeTabId, first.tabId);
    });

    test('a relative CLI spelling focuses the tab opened absolutely', () async {
      final path = await writeProjectFile('riscv-soc');
      await root.read(workspaceProvider.future);
      final opener = root.read(openProjectInWorkspaceProvider)(tabsForId);

      final first = await opener.openProject(path) as OpenProjectSuccess;
      final second =
          await opener.openProject(p.relative(path)) as OpenProjectSuccess;

      expect(second.deduped, isTrue);
      expect(second.tabId, first.tabId);
      expect(root.read(workspaceProvider).requireValue.tabs, hasLength(1));
    });

    test('a deduped open leaves the existing tab state alone', () async {
      // Re-running the engines on a project the user is already looking at
      // would discard their current run and reset the violation table. The
      // right answer to "open something already open" is to bring it
      // forward.
      final path = await writeProjectFile('riscv-soc');
      await root.read(workspaceProvider.future);
      final opener = root.read(openProjectInWorkspaceProvider)(tabsForId);

      final first = await opener.openProject(path) as OpenProjectSuccess;
      final tabId = first.tabId!;
      final tab = tabsForId(tabId);
      tab.read(violationTableStateProvider.notifier).setRuleSubstring('clk');

      await opener.openProject(path);

      expect(
        tabsForId(tabId).read(violationTableStateProvider).ruleSubstring,
        'clk',
      );
    });

    test('two projects open into two isolated tab containers', () async {
      final pathA = await writeProjectFile('alpha');
      final pathB = await writeProjectFile('beta');
      await root.read(workspaceProvider.future);
      final opener = root.read(openProjectInWorkspaceProvider)(tabsForId);

      expect(await opener.openProject(pathA), isA<OpenProjectSuccess>());
      expect(await opener.openProject(pathB), isA<OpenProjectSuccess>());

      final workspace = root.read(workspaceProvider).requireValue;
      expect(workspace.tabs, hasLength(2));
      final tabA = tabsForId(workspace.tabs.first.id);
      final tabB = tabsForId(workspace.tabs.last.id);
      expect(tabA.read(currentProjectProvider)?.name, 'alpha');
      expect(tabB.read(currentProjectProvider)?.name, 'beta');
      expect(root.read(currentProjectProvider), isNull);
    });

    group('through a design manifest', () {
      Future<String> writeDesign(String manifestName) async {
        final project = await writeProjectFile('uart');
        final manifest = p.join(tempDir.path, manifestName);
        await File(manifest).writeAsString(
          'version: 1\nname: uart\nartifacts:\n'
          '  lint: ${p.basename(project)}\n',
        );
        return manifest;
      }

      test('a <design>.crux-project opens the lint project it names, with '
          'no rename notice', () async {
        final manifest = await writeDesign('uart.crux-project');
        await root.read(workspaceProvider.future);
        final opener = root.read(openProjectInWorkspaceProvider)(tabsForId);

        final result = await opener.openProject(manifest);

        expect(result, isA<OpenProjectSuccess>());
        expect((result as OpenProjectSuccess).project.name, 'uart');
        expect(result.legacyManifestRenameTo, isNull);
        final tab = tabsForId(result.tabId!);
        expect(
          tab.read(currentProjectProvider.notifier).projectFilePath,
          endsWith('uart.lintcrux'),
        );
      });

      test('a legacy bare .crux-project still opens and names the file to '
          'rename it to', () async {
        final manifest = await writeDesign('.crux-project');
        await root.read(workspaceProvider.future);
        final opener = root.read(openProjectInWorkspaceProvider)(tabsForId);

        final result = await opener.openProject(manifest);

        expect(result, isA<OpenProjectSuccess>());
        expect(
          (result as OpenProjectSuccess).legacyManifestRenameTo,
          '${p.basename(tempDir.resolveSymbolicLinksSync())}.crux-project',
        );
      });

      test(
        'a folder holding two manifests opens nothing and names both',
        () async {
          final manifest = await writeDesign('uart.crux-project');
          File(
            p.join(tempDir.path, '.crux-project'),
          ).writeAsStringSync('version: 1\n');
          await root.read(workspaceProvider.future);
          final opener = root.read(openProjectInWorkspaceProvider)(tabsForId);

          final result = await opener.openProject(manifest);

          expect(result, isA<OpenProjectManifestAmbiguous>());
          final candidates = (result as OpenProjectManifestAmbiguous)
              .error
              .candidates
              .map(p.basename);
          expect(
            candidates,
            unorderedEquals(['.crux-project', 'uart.crux-project']),
          );
          expect(root.read(workspaceProvider).requireValue.tabs, isEmpty);
        },
      );
    });

    test(
      'returns failure for a missing file without mutating any scope',
      () async {
        await root.read(workspaceProvider.future);
        final opener = root.read(openProjectInWorkspaceProvider)(tabsForId);
        final result = await opener.openProject(
          p.join(tempDir.path, 'missing.lintcrux'),
        );
        expect(result, isA<OpenProjectFailure>());
        expect(root.read(workspaceProvider).requireValue.tabs, isEmpty);
        expect(root.read(currentProjectProvider), isNull);
      },
    );
  });

  group('OpenProjectInWorkspace.openSession', () {
    Future<String> writeSessionFile(
      String name,
      LintcruxSession session,
    ) async {
      final path = p.join(tempDir.path, '$name.lintcrux-session');
      await const SessionService().save(path, session);
      return path;
    }

    test(
      'opens the referenced project then replays the filter/sort state '
      "onto the NEW TAB's violation-table provider",
      () async {
        final projectPath = await writeProjectFile('demo');
        final session = LintcruxSession(
          projectPath: projectPath,
          activeSeverities: const {Severity.error, Severity.warning},
          activeEngineIds: const {'verilator'},
          ruleSubstring: 'UNUSED',
          fileGlob: '*.sv',
          sortColumn: ViolationTableColumn.file,
          sortAscending: false,
        );
        final sessionPath = await writeSessionFile('demo', session);

        await root.read(workspaceProvider.future);
        final opener = root.read(openProjectInWorkspaceProvider)(tabsForId);
        final result = await opener.openSession(sessionPath);
        expect(result, isA<OpenProjectSuccess>());

        final workspace = root.read(workspaceProvider).requireValue;
        expect(workspace.tabs, hasLength(1));
        final tab = tabsForId(workspace.tabs.single.id);
        final tableState = tab.read(violationTableStateProvider);
        expect(tableState.ruleSubstring, 'UNUSED');
        expect(tableState.fileGlob, '*.sv');
        expect(tableState.severities, {Severity.error, Severity.warning});
        expect(tableState.engineIds, {'verilator'});
        expect(tableState.sortColumn, ViolationTableColumn.file);
        expect(
          tableState.sortAscending,
          isFalse,
          reason:
              'the session captured a descending sort — replay must not '
              'silently reset it to ascending',
        );

        // The rest of the session (including the export path itself) is
        // mirrored onto the tab's persisted payload.
        final payload = workspace.tabs.single.payload;
        expect(payload.sessionExportPath, sessionPath);
        expect(payload.ruleSubstring, 'UNUSED');
        expect(payload.projectPath, projectPath);
      },
    );

    test('returns failure when the session file does not exist', () async {
      await root.read(workspaceProvider.future);
      final opener = root.read(openProjectInWorkspaceProvider)(tabsForId);
      final result = await opener.openSession(
        p.join(tempDir.path, 'missing.lintcrux-session'),
      );
      expect(result, isA<OpenProjectFailure>());
      expect(root.read(workspaceProvider).requireValue.tabs, isEmpty);
    });

    test(
      'propagates the underlying project-open failure when the session '
      'references a project that no longer exists',
      () async {
        final session = LintcruxSession(
          projectPath: p.join(tempDir.path, 'gone.lintcrux'),
        );
        final sessionPath = await writeSessionFile('orphan', session);

        await root.read(workspaceProvider.future);
        final opener = root.read(openProjectInWorkspaceProvider)(tabsForId);
        final result = await opener.openSession(sessionPath);
        expect(result, isA<OpenProjectFailure>());
        expect(root.read(workspaceProvider).requireValue.tabs, isEmpty);
      },
    );
  });

  group('OpenProjectInWorkspace.openWorkspace', () {
    test(
      "hydrates every tab's per-tab currentProjectProvider from its own "
      'project file',
      () async {
        final pathA = await writeProjectFile('alpha');
        final pathB = await writeProjectFile('beta');
        await root.read(workspaceProvider.future);
        final opener = root.read(openProjectInWorkspaceProvider)(tabsForId);
        await opener.openProject(pathA);
        await opener.openProject(pathB);

        final built = root.read(workspaceProvider).requireValue;
        final namedPath = p.join(tempDir.path, 'team.lintcrux-workspace');
        await root.read(workspaceServiceProvider).saveToPath(namedPath, built);

        // Simulate a fresh app start: brand-new tab containers, as if
        // no project had ever been loaded.
        tabContainers.clear();

        final error = await opener.openWorkspace(namedPath);
        expect(error, isNull);

        final reloaded = root.read(workspaceProvider).requireValue;
        expect(reloaded.tabs, hasLength(2));
        final tabA = tabsForId(reloaded.tabs.first.id);
        final tabB = tabsForId(reloaded.tabs.last.id);
        expect(tabA.read(currentProjectProvider)?.name, 'alpha');
        expect(tabB.read(currentProjectProvider)?.name, 'beta');
        expect(root.read(currentProjectProvider), isNull);
      },
    );

    test(
      'skips a tab whose project file is missing instead of aborting the '
      'whole workspace load',
      () async {
        final pathA = await writeProjectFile('alpha');
        final pathB = await writeProjectFile('beta');
        await root.read(workspaceProvider.future);
        final opener = root.read(openProjectInWorkspaceProvider)(tabsForId);
        await opener.openProject(pathA);
        await opener.openProject(pathB);

        final built = root.read(workspaceProvider).requireValue;
        final namedPath = p.join(tempDir.path, 'team.lintcrux-workspace');
        await root.read(workspaceServiceProvider).saveToPath(namedPath, built);

        // Delete tab B's project file after the workspace document was
        // saved, so the reload hits the per-tab try/catch skip path.
        await File(pathB).delete();
        tabContainers.clear();

        final error = await opener.openWorkspace(namedPath);
        expect(
          error,
          isNull,
          reason:
              'a single missing project must not '
              'abort the whole workspace load',
        );

        final reloaded = root.read(workspaceProvider).requireValue;
        expect(reloaded.tabs, hasLength(2));
        final tabA = tabsForId(reloaded.tabs.first.id);
        final tabB = tabsForId(reloaded.tabs.last.id);
        expect(tabA.read(currentProjectProvider)?.name, 'alpha');
        // Skipped: the tab still exists in the workspace document but
        // its per-tab container never received a project.
        expect(tabB.read(currentProjectProvider), isNull);
      },
    );

    test(
      'a malformed workspace document surfaces a load error rather than '
      'silently loading empty — crux_workspace loadFromPath now surfaces '
      'corrupt documents instead of swallowing them',
      () async {
        // crux-shared 3e3ddce: WorkspaceService.loadFromPath
        // raises WorkspaceLoadException on a corrupt document instead of
        // returning the canonical empty workspace. openWorkspace catches it
        // and returns the message so the caller can surface it — silently
        // discarding the user's file was the bug being fixed.
        final badPath = p.join(tempDir.path, 'broken.lintcrux-workspace');
        await File(badPath).writeAsString('not json');
        await root.read(workspaceProvider.future);
        final opener = root.read(openProjectInWorkspaceProvider)(tabsForId);

        final error = await opener.openWorkspace(badPath);
        expect(error, isNotNull);
        expect(error, contains('broken.lintcrux-workspace'));
      },
    );

    test(
      'returns an error message (rather than throwing) when the '
      'underlying WorkspaceService raises',
      () async {
        final throwingRoot = ProviderContainer(
          overrides: [
            ...telemetryDeclinedOverrides(),
            engineRegistryProvider.overrideWithValue(
              EngineRegistry(const []),
            ),
            workspaceServiceProvider.overrideWithValue(
              _ThrowingLoadWorkspaceService(),
            ),
          ],
        );
        addTearDown(throwingRoot.dispose);
        await throwingRoot.read(workspaceProvider.future);
        final opener = throwingRoot.read(openProjectInWorkspaceProvider)(
          (tabId) => throwingRoot,
        );

        final error = await opener.openWorkspace(
          p.join(tempDir.path, 'irrelevant.lintcrux-workspace'),
        );
        expect(error, contains('simulated load failure'));
      },
    );
  });
}
