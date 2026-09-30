// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_projects/crux_projects.dart';
import 'package:path/path.dart' as p;

/// An in-memory multi-project [ProjectRegistry] with the Pro overlay's
/// semantics — open appends, close moves to recents, pins survive close-all,
/// hydration can arrive late — and no filesystem.
///
/// Open core tests the tab-to-registry sync against the multi-project
/// contract, not against the Pro implementation of it: that implementation is
/// the paid capability and lives with the Pro overlays' private shared code,
/// so no open-core test can import it. This double models the contract's
/// observable behaviour, including the two properties the sync's regression
/// tests depend on:
///
/// - **Paths are canonicalised on open**, as the persistent registry does
///   (`p.normalize(p.absolute(path))`), so a relative or `..`-bearing tab path
///   and the registry's spelling of the same project differ — which is the
///   spelling mismatch the sync must survive.
/// - **Hydration can arrive after the workspace resolved.** A registry built
///   with [pending] starts empty and publishes that workspace only when
///   [hydrate] is called, the way the Pro overlay's deferred proxy publishes
///   its persisted open-project list after the tab document has already
///   loaded. That ordering is the whole mechanism behind the declined-restore
///   regression.
///
/// `test/services/violations/violation_store_per_project_test.dart` carries a
/// smaller double of its own that only needs open and activate.
class FakeMultiProjectRegistry implements ProjectRegistry {
  /// Creates an empty registry, or one that will publish [pending] on
  /// [hydrate].
  FakeMultiProjectRegistry({
    ProjectWorkspace? pending,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _pending = pending;
  }

  ProjectWorkspace? _pending;
  final DateTime Function() _clock;
  ProjectWorkspace _ws = ProjectWorkspace.empty();
  final List<StreamController<ProjectWorkspace>> _subs =
      <StreamController<ProjectWorkspace>>[];

  /// The canonical spelling the registry records for [path] — the same
  /// transform the persistent registry applies, so a test can compute the
  /// value an assertion should expect.
  static String canonicalize(String path) => p.normalize(p.absolute(path));

  /// Builds the descriptor the registry would record for [path].
  static ProjectDescriptor describe(String path, {DateTime? at}) {
    final canonical = canonicalize(path);
    final now = at ?? DateTime.now();
    return ProjectDescriptor(
      id: ProjectDescriptor.idForPath(canonical),
      displayName: p.basename(canonical),
      projectPath: canonical,
      loadedAt: now,
      lastAccessedAt: now,
    );
  }

  /// Publishes the workspace this registry was built with, as a late restore
  /// would. A no-op when there is nothing pending.
  void hydrate() {
    final pending = _pending;
    if (pending == null) return;
    _pending = null;
    _ws = pending;
    _publish();
  }

  void _publish() {
    for (final s in _subs) {
      if (!s.isClosed) s.add(_ws);
    }
  }

  @override
  ProjectWorkspace get current => _ws;

  @override
  Stream<ProjectWorkspace> watch() {
    late StreamController<ProjectWorkspace> controller;
    controller = StreamController<ProjectWorkspace>(
      onCancel: () => _subs.remove(controller),
    );
    _subs.add(controller);
    scheduleMicrotask(() {
      if (!controller.isClosed) controller.add(_ws);
    });
    return controller.stream;
  }

  @override
  Future<ProjectDescriptor> openProject(String projectPath) async {
    final canonical = canonicalize(projectPath);
    final id = ProjectDescriptor.idForPath(canonical);
    final existing = _ws.openProjects.where((d) => d.id == id);
    if (existing.isNotEmpty) {
      await setActiveProject(id);
      return _ws.activeProject!;
    }
    final descriptor = describe(canonical, at: _clock());
    _ws = ProjectWorkspace(
      openProjects: <ProjectDescriptor>[..._ws.openProjects, descriptor],
      activeProjectId: descriptor.id,
      recentProjects: _ws.recentProjects.where((d) => d.id != id).toList(),
    );
    _publish();
    return descriptor;
  }

  @override
  Future<void> closeProject(String projectId, {bool hardClose = false}) async {
    final closing = _ws.openProjects.where((d) => d.id == projectId);
    if (closing.isEmpty) return;
    final remaining = _ws.openProjects.where((d) => d.id != projectId).toList();
    final recents = hardClose
        ? _ws.recentProjects
        : <ProjectDescriptor>[
            closing.single.copyWith(isPinned: false),
            ..._ws.recentProjects.where((d) => d.id != projectId),
          ];
    _ws = ProjectWorkspace(
      openProjects: remaining,
      activeProjectId: _ws.activeProjectId == projectId
          ? (remaining.isEmpty ? null : remaining.last.id)
          : _ws.activeProjectId,
      recentProjects: recents,
    );
    _publish();
  }

  @override
  Future<void> closeAllProjects() async {
    final pinned = _ws.openProjects.where((d) => d.isPinned).toList();
    final closed = _ws.openProjects.where((d) => !d.isPinned).toList();
    _ws = ProjectWorkspace(
      openProjects: pinned,
      activeProjectId: pinned.isEmpty ? null : pinned.last.id,
      recentProjects: <ProjectDescriptor>[
        ...closed,
        ..._ws.recentProjects.where(
          (r) => !closed.any((c) => c.id == r.id),
        ),
      ],
    );
    _publish();
  }

  @override
  Future<void> setActiveProject(String projectId) async {
    if (!_ws.openProjects.any((d) => d.id == projectId)) return;
    _ws = _ws.copyWith(
      activeProjectId: projectId,
      openProjects: _ws.openProjects
          .map(
            (d) => d.id == projectId ? d.copyWith(lastAccessedAt: _clock()) : d,
          )
          .toList(),
    );
    _publish();
  }

  @override
  Future<void> pinProject(String projectId, {required bool pinned}) async {
    if (!_ws.openProjects.any((d) => d.id == projectId)) return;
    _ws = _ws.copyWith(
      openProjects: _ws.openProjects
          .map((d) => d.id == projectId ? d.copyWith(isPinned: pinned) : d)
          .toList(),
    );
    _publish();
  }

  @override
  Future<void> reorderProjects(List<String> newOrderIds) async {
    final byId = <String, ProjectDescriptor>{
      for (final d in _ws.openProjects) d.id: d,
    };
    final ordered = <ProjectDescriptor>[
      for (final id in newOrderIds)
        if (byId.containsKey(id)) byId[id]!,
    ];
    if (ordered.length != byId.length) return;
    _ws = _ws.copyWith(openProjects: ordered);
    _publish();
  }

  @override
  Future<void> clearRecentProject(String projectId) async {
    if (!_ws.recentProjects.any((d) => d.id == projectId)) return;
    _ws = _ws.copyWith(
      recentProjects: _ws.recentProjects
          .where((d) => d.id != projectId)
          .toList(),
    );
    _publish();
  }

  @override
  Future<void> shutdownAll() async {
    _ws = ProjectWorkspace.empty();
    _publish();
  }
}
