// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_project/crux_project.dart';
import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:lintcrux/domain/models/lint_project.dart';

/// Result of a project-open attempt
/// (`OpenProjectInWorkspace.openProject` and friends).
sealed class OpenProjectResult {
  const OpenProjectResult();
}

/// Project loaded successfully; [project] is the parsed model.
class OpenProjectSuccess extends OpenProjectResult {
  /// Creates a success result.
  const OpenProjectSuccess(
    this.project, {
    this.tabId,
    this.deduped = false,
    this.legacyManifestRenameTo,
  });

  /// The loaded project.
  final LintProject project;

  /// Workspace tab now showing [project] — the tab that was created, or the
  /// one that was focused when [deduped] is true.
  ///
  /// Nullable because a few call sites construct a success result without a
  /// workspace (unit tests, the SARIF-only web viewer path).
  final crux.TabId? tabId;

  /// `true` when the project was already open and its existing tab was
  /// focused instead of a second tab being created.
  ///
  /// Callers that want to know whether they just created a tab — the session
  /// importer, which replays filter state onto "the tab it opened" — must
  /// read [tabId] rather than assuming the newest tab is theirs.
  final bool deduped;

  /// Set when the project was opened through a design manifest still named
  /// with the legacy bare `.crux-project`: the `<design>.crux-project` file
  /// name to rename it to. The caller shows the deprecation notice once, in
  /// the user's language.
  final String? legacyManifestRenameTo;
}

/// Project load failed; [message] is suitable for surfacing in a
/// snackbar.
class OpenProjectFailure extends OpenProjectResult {
  /// Creates a failure result.
  const OpenProjectFailure(this.message);

  /// English-only failure message.
  final String message;
}

/// The design manifest's directory holds more than one manifest, so the
/// design is ambiguous and nothing was opened.
///
/// A [OpenProjectFailure] like any other — [message] is the English
/// description — but it carries the conflict as data so the UI can explain it
/// in the user's language.
class OpenProjectManifestAmbiguous extends OpenProjectFailure {
  /// Creates the failure from the shared package's [error].
  OpenProjectManifestAmbiguous(this.error) : super(error.message);

  /// The directory searched and every manifest found in it.
  final CruxProjectAmbiguousException error;
}

// NOTE: every open flow — File → Open, CLI positional paths, filelist
// import, session/workspace restore — routes through
// `OpenProjectInWorkspace`, which loads the project into a NEW TAB's
// per-tab `currentProjectProvider`. There is deliberately no
// root-container project loader: the per-project extension-point
// stores (waivers, baseline, bookmarks, filter presets, lint cache,
// Verible) are per-tab, and a root-scope `currentProjectProvider`
// write would hand them a project that can diverge from what any tab
// shows.
