// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/core/app_info/about_providers.dart';
import 'package:lintcrux/core/help_urls.dart';
import 'package:lintcrux/core/lintcrux_url_launcher.dart';
import 'package:lintcrux/features/workspace/providers/recent_projects_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/shared/widgets/glowing_app_icon.dart';

/// LintCrux's content composed into `crux_workspace`'s
/// [crux.EmptyCanvasState] shell when the workspace has zero tabs.
///
/// Renders the empty-canvas shell with:
/// * the LintCrux title + subtitle,
/// * a recent-projects section (sourced from
///   [recentProjectsProvider]),
/// * a recent-workspaces section (currently an empty placeholder),
/// * the primary actions wired through callbacks supplied by the host
///   scaffold (so the empty-canvas widget doesn't re-implement the
///   file-picker / workspace-open logic).
class EmptyCanvasContent extends ConsumerWidget {
  /// Creates an [EmptyCanvasContent].
  const EmptyCanvasContent({
    required this.onOpenProject,
    required this.onOpenSession,
    required this.onOpenWorkspace,
    required this.onNewProject,
    required this.onOpenRecentProject,
    this.onImportSarif,
    super.key,
  });

  /// Invoked when the user taps the "Open Project…" button.
  final VoidCallback onOpenProject;

  /// Invoked when the user taps the "Open Session…" button.
  final VoidCallback onOpenSession;

  /// Invoked when the user taps the "Open Workspace…" button.
  final VoidCallback onOpenWorkspace;

  /// Invoked when the user taps the "New Project…" button. Scaffolds a
  /// real, populatable `.lintcrux` project at a user-chosen save location
  /// (name from the basename, root from the parent directory) and opens
  /// it as a tab; the user adds sources / engines from project Settings.
  /// See `ViewerScaffold._handleNewProject`.
  final VoidCallback onNewProject;

  /// Invoked when the user taps a row in the recent-projects list.
  /// Receives the absolute path of the chosen project.
  final void Function(String path) onOpenRecentProject;

  /// Invoked when the user taps the "Import SARIF report…" button, or
  /// `null` to hide it. Imports a CI-generated SARIF report into a
  /// read-only viewer without re-running engines.
  final VoidCallback? onImportSarif;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final recentProjects = ref.watch(recentProjectsProvider);
    // The running version, shown as a muted line under the subtitle. On web
    // there is no native menu bar, so this is the only always-visible place a
    // user can read the version without knowing the palette / overflow About
    // entry points. Resolves in milliseconds; renders nothing until then.
    final version = ref.watch(aboutBuildInfoProvider).value?.version;

    return crux.EmptyCanvasState(
      header: const GlowingAppIcon(size: 72),
      title: l10n.emptyCanvasTitle,
      subtitle: l10n.emptyCanvasSubtitle,
      versionLabel: version == null ? null : l10n.emptyCanvasVersion(version),
      recentFilesSection: _RecentSection(
        heading: l10n.emptyCanvasRecentProjectsHeading,
        emptyPlaceholder: l10n.emptyCanvasNoRecentProjects,
        items: recentProjects,
        iconBuilder: (_) => const Icon(Icons.folder_outlined),
        onTap: onOpenRecentProject,
        theme: theme,
      ),
      recentWorkspacesSection: _RecentSection(
        heading: l10n.emptyCanvasRecentWorkspacesHeading,
        emptyPlaceholder: l10n.emptyCanvasNoRecentWorkspaces,
        items: const <String>[],
        iconBuilder: (_) => const Icon(Icons.workspaces_outlined),
        onTap: (_) {},
        theme: theme,
      ),
      primaryActions: [
        FilledButton.icon(
          onPressed: onOpenProject,
          icon: const Icon(Icons.folder_open),
          label: Text(l10n.emptyCanvasOpenProjectButton),
        ),
        OutlinedButton.icon(
          onPressed: onOpenWorkspace,
          icon: const Icon(Icons.workspaces),
          label: Text(l10n.emptyCanvasOpenWorkspaceButton),
        ),
        OutlinedButton.icon(
          onPressed: onOpenSession,
          icon: const Icon(Icons.bookmark_outline),
          label: Text(l10n.emptyCanvasOpenSessionButton),
        ),
        // Scaffolds a real, populatable `.lintcrux` project at the chosen
        // save location and opens it as a tab (see
        // `ViewerScaffold._handleNewProject`) — a genuine "New", not an
        // empty unpopulatable tab.
        OutlinedButton.icon(
          onPressed: onNewProject,
          icon: const Icon(Icons.add),
          label: Text(l10n.emptyCanvasNewProjectButton),
        ),
        // Import a CI-generated SARIF report into a read-only
        // viewer without re-running engines. Rendered only when the host
        // supplies the callback (desktop).
        if (onImportSarif != null)
          OutlinedButton.icon(
            onPressed: onImportSarif,
            icon: const Icon(Icons.file_download_outlined),
            label: Text(l10n.actionImportSarif),
          ),
      ],
      // What the other three products do for someone who is here, reading a
      // lint report. Above the suite line, which is the quieter version of
      // the same statement.
      peers: crux.CruxSuitePeers(
        heading: l10n.emptyCanvasPeersHeading,
        entries: [
          crux.CruxSuitePeerEntry(
            product: crux.CruxSuiteProduct.waveCrux,
            blurb: l10n.emptyCanvasPeerWaveCrux,
          ),
          crux.CruxSuitePeerEntry(
            product: crux.CruxSuiteProduct.netCrux,
            blurb: l10n.emptyCanvasPeerNetCrux,
          ),
          crux.CruxSuitePeerEntry(
            product: crux.CruxSuiteProduct.simCrux,
            blurb: l10n.emptyCanvasPeerSimCrux,
          ),
        ],
        onOpenPeer: (peer) => unawaited(
          lintcruxLaunchUrl(Uri.parse(HelpUrls.suitePeer(peer.slug))),
        ),
      ),
      footer: crux.CruxSuiteFooter(
        label: l10n.emptyCanvasSuiteFooter,
        onTap: () =>
            unawaited(lintcruxLaunchUrl(Uri.parse(HelpUrls.suiteHome))),
      ),
    );
  }
}

/// Internal helper rendering one labeled "Recent X" section with a
/// list of tappable rows or an empty-state placeholder.
class _RecentSection extends StatelessWidget {
  const _RecentSection({
    required this.heading,
    required this.emptyPlaceholder,
    required this.items,
    required this.iconBuilder,
    required this.onTap,
    required this.theme,
  });

  final String heading;
  final String emptyPlaceholder;
  final List<String> items;
  final Widget Function(String item) iconBuilder;
  final void Function(String item) onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          heading,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Text(
            emptyPlaceholder,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final item in items)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: iconBuilder(item),
              title: Text(item, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => onTap(item),
            ),
      ],
    );
  }
}
