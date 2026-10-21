// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/features/sources/providers/source_removal.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:path/path.dart' as p;

/// The project's source files and pin-constraint files, and the only way to
/// take one back out.
///
/// Adding a source was a one-way door: the file picker appended to the
/// project and nothing anywhere listed what a project contained. A user who
/// added the wrong file had no way to see that they had, let alone undo it —
/// the only recovery was editing `.lintcrux` by hand or starting a new
/// project, and neither is discoverable from inside the app.
///
/// Paths are shown basename-first with the directory beneath, because the
/// basename is what distinguishes two entries and a column of long absolute
/// paths distinguishes nothing at the point the eye lands.
///
/// Constraint files (`.pcf`, `.lpf`, `.cst`) are listed in their own section
/// beneath the sources, filled from `.lintcrux`, an EDAM import and the CLI,
/// with the same per-row remove. There is no add action here.
class SourcesPanel extends ConsumerWidget {
  /// Creates the panel.
  const SourcesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final project = ref.watch(currentProjectProvider);
    if (project == null) {
      return CruxPanelEmptyState(message: l10n.sourcesPanelNoProject);
    }
    final sources = project.sourceFiles;
    final constraints = project.constraintFiles;
    if (sources.isEmpty && constraints.isEmpty) {
      return CruxPanelEmptyState(message: l10n.sourcesPanelEmpty);
    }
    final scheme = Theme.of(context).colorScheme;

    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    // Built lazily: a design pulled in through FuseSoC can list thousands of
    // sources. Each non-empty section is a header row and then its files.
    final sourceRows = sources.isEmpty ? 0 : sources.length + 1;
    final constraintRows = constraints.isEmpty ? 0 : constraints.length + 1;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sourceRows + constraintRows,
      itemBuilder: (context, index) {
        if (index < sourceRows) {
          return index == 0
              ? header(l10n.sourcesCount(sources.length))
              : _SourceRow(path: sources[index - 1], projectName: project.name);
        }
        final i = index - sourceRows;
        return i == 0
            ? header(l10n.constraintsCount(constraints.length))
            : _SourceRow(
                path: constraints[i - 1],
                projectName: project.name,
                kind: ProjectFileKind.constraint,
              );
      },
    );
  }
}

class _SourceRow extends ConsumerWidget {
  const _SourceRow({
    required this.path,
    required this.projectName,
    this.kind = ProjectFileKind.source,
  });

  final String path;
  final String projectName;
  final ProjectFileKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      // The full path is the tooltip rather than the label: two files with the
      // same basename in different directories must be distinguishable, but
      // not at the cost of making every row unreadable.
      title: Tooltip(
        message: path,
        child: Text(
          p.basename(path),
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
      subtitle: Text(
        p.dirname(path),
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 16),
        tooltip: l10n.sourcesRemoveTooltip,
        onPressed: () => removeSourceFromProject(
          context,
          ref,
          absolutePath: path,
          projectName: projectName,
          kind: kind,
        ),
      ),
    );
  }
}
