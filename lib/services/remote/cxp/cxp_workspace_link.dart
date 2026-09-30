// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/remote/cxp/cxp_outbound.dart';
import 'package:lintcrux/services/remote/cxp/cxp_project_open_handle.dart';
import 'package:lintcrux/services/workspace/active_tab_container_handle.dart';
import 'package:path/path.dart' as p;

/// The shared-workspace artifact kind LintCrux both produces and consumes.
///
/// LintCrux's primary design input is a `.lintcrux` project. It *produces* a
/// `source` record naming the opened project file (the producer side, see
/// [publishLintcruxProjectArtifact]) and *consumes* one when a peer asks it to
/// open a design it has none of loaded (the consumer side, in
/// `cxp_server_provider.dart` / `lintcrux_cxp_request_handler.dart`).
const String kCxpLintcruxSourceKind = 'source';

/// LintCrux's producer short-name stamped into workspace records.
const String kLintcruxProducer = 'lintcrux';

/// The directories the user has opened, as CXP §11's containment rule
/// consumes them.
///
/// Two sources, both "the user opened this":
///
/// * the containing directory of every `.lintcrux` project file the user has
///   opened — every workspace tab's and every Recent projects entry, published
///   through [CxpProjectOpenHandle.projectPaths]. The Recent list is what lets
///   a peer's cross-probe land on a design whose tab was closed, through the
///   `crux.design_id` fallback: without it the only project this rule admits
///   is one already open, and opening a design a peer names — the reason the
///   workspace fallback exists — could never succeed;
/// * the ACTIVE tab's project root ([LintProject.rootPath]) and the
///   containing directory of each of its source files, because a filelist
///   may name files outside the project tree. Only the active tab's project
///   model is reachable from root scope (`ActiveTabContainerHandle` resolves
///   one container, not all of them), so a background tab contributes its
///   project directory and not its out-of-tree sources.
///
/// These roots guard the `crux.design_id` fallback and every path handed to
/// an editor. `request_open_artifact` is not rooted at all: see
/// [kCxpOpenArtifactContainment] for why it is held to the floor.
///
/// Read on every containment check rather than snapshotted when the server
/// starts, so a project opened after CXP came up is one the user opened.
Iterable<String> cxpOpenDirectories(Ref ref) {
  final roots = <String>{
    for (final path
        in ref.read(cxpProjectOpenHandleProvider).openedProjectPaths)
      if (path.isNotEmpty) p.dirname(path),
  };
  final active = ref.read(activeTabContainerHandleProvider).activeContainer;
  final project = active == null
      ? ref.read(currentProjectProvider)
      : active.read(currentProjectProvider);
  if (project != null) {
    if (project.rootPath.isNotEmpty) roots.add(project.rootPath);
    for (final file in project.sourceFiles) {
      if (file.isNotEmpty) roots.add(p.dirname(file));
    }
  }
  return roots;
}

/// The rooted [CxpPathContainment]: a peer-supplied path must lie inside
/// [cxpOpenDirectories].
///
/// One instance, so the routes that keep the roots apply the *same* rule,
/// which is what CXP §11 requires of an artifact resolved through our own
/// records: [cxpWorkspaceStoreProvider] screens what it resolves for the
/// `crux.design_id` fallback, the `resolveAndOpenArtifact` wiring in
/// `cxp_server_provider.dart` checks the project path that fallback is about
/// to open, and `LintCruxCxpRequestHandler` checks the value it is about to
/// hand to an editor argv (`request_open_source`).
///
/// `request_open_artifact` is held to [kCxpOpenArtifactContainment] instead,
/// and so is `LocalCxpServer`'s screen of the wire, because that one rule
/// covers the artifact request's hint as well as `request_open_source`.
final Provider<CxpPathContainment> cxpPathContainmentProvider =
    Provider<CxpPathContainment>(
      (ref) => CxpPathContainment(roots: () => cxpOpenDirectories(ref)),
    );

/// The rule a `request_open_artifact` is held to: CXP §11.3's floor, and
/// not the directories the user has opened.
///
/// The floor refuses what a path must never be on its way into an open:
/// empty, relative (resolved against whatever directory LintCrux was
/// launched from), carrying a NUL, or padded with white space. It judges the
/// exact string the caller is about to open, so a padded path is refused
/// rather than trimmed into a different file.
///
/// It is not rooted, because on this route a rooted rule is secure and
/// useless at once. `request_open_artifact` exists to open a project LintCrux
/// does not have open: the VS Code extension's "Open in LintCrux Desktop"
/// sends it for the `.lintcrux` project of the design the user is editing,
/// which is, as often as not, one this installation has never opened. Rooted
/// on the open tabs and the Recent projects, the rule refused exactly the
/// request the route serves, and the roots bought nothing to pay for that:
///
/// * the sender is already a same-user process. Since CXP 1.2 a peer must
///   present the per-process token LintCrux publishes in its manifest, which
///   only a process that can read this user's application data can do, and
///   such a process can already read any file LintCrux could be asked to
///   open;
/// * opening a project parses it and runs the linters over its sources.
///   Which linters, and which binaries, come from this installation's
///   Settings, not from the project file. A project can carry its own flags
///   for those linters, but it carries them whether the user opens it from
///   the file picker or VS Code asks for it, and the process asking could
///   run the same linters on the same project itself.
///
/// WaveCrux and NetCrux took the same decision for the hand-off that opens
/// their artifacts.
///
/// The roots stay where they still buy something
/// ([cxpPathContainmentProvider]): the `crux.design_id` fallback resolves an
/// id a peer attached to a cross-probe through store records nobody asked
/// LintCrux to open, and `request_open_source` hands its path to an editor
/// command line.
const CxpPathContainment kCxpOpenArtifactContainment = CxpPathContainment();

/// The shared design→artifact link store.
///
/// A single instance rooted at the suite-shared workspace directory
/// (`sharedCxpWorkspaceDirectory()`, the sibling of the `peers/` directory the
/// discovery manifests live in). Overridable in tests to redirect the store at
/// a temp directory so no test touches the real per-user workspace.
///
/// Carries [cxpPathContainmentProvider] so a record written by a peer — the
/// workspace directory is user-writable, and the sender chose the `design_id`
/// that selects the record — cannot name a file outside the directories this
/// process has open (CXP §11). `request_open_artifact` reads the same records
/// under its own rule instead: see [resolveOpenArtifactProjectPath].
final Provider<CxpWorkspaceStore> cxpWorkspaceStoreProvider =
    Provider<CxpWorkspaceStore>(
      (ref) =>
          CxpWorkspaceStore(containment: ref.watch(cxpPathContainmentProvider)),
    );

/// Derives the shared CXP `design_id` for [project] — the one token every app
/// keys the workspace manifest and `crux.design_id` metadata by.
///
/// LintCrux's "primary design input" per the design-id derivation contract is
/// the `project.lintcrux` directory, which is exactly [LintProject.rootPath].
/// The one shared [cxpDesignIdForPath] helper canonicalizes it so the token is
/// byte-identical to the id SimCrux / NetCrux / WaveCrux compute for the same
/// design folder.
String cxpLintcruxDesignId(LintProject project) =>
    cxpDesignIdForPath(project.rootPath);

/// Records the just-opened project at [projectPath] in the shared workspace so
/// a peer that receives a cross-probe it cannot satisfy locally can resolve and
/// open this design's LintCrux project.
///
/// The record is keyed by the design's `design_id` — derived from the project
/// file's containing directory via the one shared [cxpDesignIdForPath] helper,
/// so it byte-matches the id the other apps compute for the same design folder.
///
/// Gated on the CXP server running (read through the services-layer
/// [CxpServerHandle], so this file stays in the services layer without reaching
/// up into the feature lifecycle): with CXP off there is no peer to serve and
/// no reason to write into the shared workspace directory — which also keeps
/// the wide swath of project-open tests from writing into the real per-user
/// workspace. Best-effort throughout: a failed upsert must never break opening
/// a project, so every error is swallowed.
Future<void> publishLintcruxProjectArtifact(
  Ref ref,
  String projectPath,
  LintProject project,
) async {
  if (ref.read(cxpServerHandleProvider).server == null) return;
  try {
    await ref
        .read(cxpWorkspaceStoreProvider)
        .upsertArtifact(
          designId: cxpDesignIdForPath(projectPath),
          kind: kCxpLintcruxSourceKind,
          path: projectPath,
          producer: kLintcruxProducer,
          topModule: project.topModule,
          basename: p.basename(projectPath),
        );
  } on Object {
    // The workspace link is a courtesy; never let a workspace write surface as
    // an error on the project-open path.
  }
}

/// Resolves the shared-workspace `source` artifact for the design named by
/// [designId], preferring an exact `design_id`+kind match and falling back to
/// the descriptive [topModule] / [basename] hints.
///
/// Returns the absolute path to open (a `.lintcrux` project file), or null when
/// the design has no `source` artifact recorded. The caller opens it through
/// LintCrux's ordinary `OpenProjectInWorkspace.openProject` path.
///
/// Reads through [cxpWorkspaceStoreProvider], so a record outside the
/// directories the user has opened resolves to null: this is the
/// `crux.design_id` fallback's resolution. `request_open_artifact` uses
/// [resolveOpenArtifactProjectPath].
String? resolveLintcruxSourceArtifactPath(
  Ref ref,
  String designId, {
  String? topModule,
  String? basename,
}) {
  if (designId.isEmpty) return null;
  final artifact = ref
      .read(cxpWorkspaceStoreProvider)
      .resolveArtifact(
        designId,
        kCxpLintcruxSourceKind,
        topModule: topModule,
        basename: basename,
      );
  return artifact?.path;
}

/// Resolves the `source` artifact recorded for [designId] the way
/// `request_open_artifact` needs it: the records [cxpWorkspaceStoreProvider]
/// reads, from the same directory, admitted by [kCxpOpenArtifactContainment]
/// rather than by the rooted rule that store carries.
///
/// Reading them through the rooted store would drop the record for a project
/// LintCrux has never opened, and the request would be refused as though
/// nothing were recorded — the failure [kCxpOpenArtifactContainment]
/// explains. The store keeps no state between reads, so a second view of the
/// directory costs nothing.
///
/// Returns the absolute path LintCrux should open, or null when the design
/// has no `source` artifact recorded.
String? resolveOpenArtifactProjectPath(Ref ref, String designId) {
  if (designId.isEmpty) return null;
  final store = ref.read(cxpWorkspaceStoreProvider);
  return CxpWorkspaceStore(
    workspaceDirectory: store.workspaceDirectory,
    ttl: store.ttl,
    containment: kCxpOpenArtifactContainment,
  ).resolveArtifact(designId, kCxpLintcruxSourceKind)?.path;
}
