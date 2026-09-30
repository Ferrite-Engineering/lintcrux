// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_projects/crux_projects.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/violation_store.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';

ProjectDescriptor _desc(String id) {
  final t = DateTime.utc(2026, 3);
  return ProjectDescriptor(
    id: id,
    displayName: '$id.lintcrux',
    projectPath: '/projects/$id.lintcrux',
    loadedAt: t,
    lastAccessedAt: t,
  );
}

Violation _violation(String engine, String ruleId) {
  return Violation(
    engineId: engine,
    ruleId: ruleId,
    severity: Severity.warning,
    message: 'msg-$ruleId',
    location: const SourceLocation(file: '/x.v', line: 1, column: 1),
  );
}

class _FakeMultiProjectRegistry implements ProjectRegistry {
  ProjectWorkspace _ws = ProjectWorkspace.empty();
  final List<StreamController<ProjectWorkspace>> _subs =
      <StreamController<ProjectWorkspace>>[];

  void _publish() {
    for (final s in _subs) {
      if (!s.isClosed) s.add(_ws);
    }
  }

  void openSync(ProjectDescriptor d) {
    _ws = ProjectWorkspace(
      openProjects: <ProjectDescriptor>[..._ws.openProjects, d],
      activeProjectId: d.id,
      recentProjects: _ws.recentProjects,
    );
    _publish();
  }

  void setActiveSync(String id) {
    if (!_ws.openProjects.any((p) => p.id == id)) return;
    _ws = _ws.copyWith(activeProjectId: id);
    _publish();
  }

  @override
  ProjectWorkspace get current => _ws;

  @override
  Stream<ProjectWorkspace> watch() {
    late StreamController<ProjectWorkspace> c;
    c = StreamController<ProjectWorkspace>(
      onListen: () => c.add(_ws),
      onCancel: () => _subs.remove(c),
    );
    _subs.add(c);
    return c.stream;
  }

  @override
  Future<ProjectDescriptor> openProject(String projectPath) async =>
      throw UnimplementedError();
  @override
  Future<void> closeProject(String projectId, {bool hardClose = false}) async {}
  @override
  Future<void> closeAllProjects() async {}
  @override
  Future<void> setActiveProject(String projectId) async {
    setActiveSync(projectId);
  }

  @override
  Future<void> pinProject(String projectId, {required bool pinned}) async {}
  @override
  Future<void> reorderProjects(List<String> newOrderIds) async {}
  @override
  Future<void> clearRecentProject(String projectId) async {}
  @override
  Future<void> shutdownAll() async {}
}

Future<void> _pump() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('violationStoreProvider per-project isolation', () {
    test(
      'each active project resolves to its own ViolationStore instance',
      () async {
        final registry = _FakeMultiProjectRegistry();
        final container = ProviderContainer(
          overrides: <Override>[
            projectRegistryProvider.overrideWithValue(registry),
          ],
        );
        addTearDown(container.dispose);
        container.listen(
          projectWorkspaceProvider,
          (_, _) {},
          fireImmediately: true,
        );
        await _pump();

        registry
          ..openSync(_desc('a'))
          ..setActiveSync('a');
        await _pump();
        final storeA = container.read(violationStoreProvider);

        registry
          ..openSync(_desc('b'))
          ..setActiveSync('b');
        await _pump();
        final storeB = container.read(violationStoreProvider);

        expect(
          identical(storeA, storeB),
          isFalse,
          reason: 'each project gets a fresh ViolationStore instance',
        );
      },
    );

    test('state written to one project store does not leak into another '
        'project store', () async {
      final registry = _FakeMultiProjectRegistry();
      final container = ProviderContainer(
        overrides: <Override>[
          projectRegistryProvider.overrideWithValue(registry),
        ],
      );
      addTearDown(container.dispose);
      container.listen(
        projectWorkspaceProvider,
        (_, _) {},
        fireImmediately: true,
      );
      await _pump();

      registry
        ..openSync(_desc('a'))
        ..setActiveSync('a');
      await _pump();
      final storeA = container.read(violationStoreProvider)
        ..replaceFromEngine('verilator', <Violation>[
          _violation('verilator', 'A1'),
          _violation('verilator', 'A2'),
        ]);
      expect(storeA.all, hasLength(2));

      registry
        ..openSync(_desc('b'))
        ..setActiveSync('b');
      await _pump();
      final storeB = container.read(violationStoreProvider);
      expect(storeB.all, isEmpty, reason: 'project B starts empty');

      storeB.replaceFromEngine('verilator', <Violation>[
        _violation('verilator', 'B1'),
      ]);
      expect(storeB.all, hasLength(1));

      // Switch back to A; A's state is preserved.
      registry.setActiveSync('a');
      await _pump();
      final storeA2 = container.read(violationStoreProvider);
      expect(
        identical(storeA, storeA2),
        isTrue,
        reason: 're-activating project A returns the same cached store',
      );
      expect(
        storeA2.all,
        hasLength(2),
        reason: 'project A retains its 2 violations across switches',
      );
    });

    test('empty-workspace sentinel resolves to a stable store too', () async {
      final registry = _FakeMultiProjectRegistry();
      final container = ProviderContainer(
        overrides: <Override>[
          projectRegistryProvider.overrideWithValue(registry),
        ],
      );
      addTearDown(container.dispose);
      container.listen(
        projectWorkspaceProvider,
        (_, _) {},
        fireImmediately: true,
      );
      await _pump();

      final s1 = container.read(violationStoreProvider);
      final s2 = container.read(violationStoreProvider);
      expect(identical(s1, s2), isTrue);
      expect(s1, isA<ViolationStore>());
    });
  });
}
