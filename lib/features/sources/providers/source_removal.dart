// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/features/run/providers/lint_run_notifier.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/project/project_file_codec.dart';
import 'package:lintcrux/services/project/project_file_service.dart';
import 'package:lintcrux/services/project/project_path_resolver.dart';
import 'package:path/path.dart' as p;

/// Removes [absolutePath] from the open project, after confirming.
///
/// **Mirrors the add path deliberately, including the awkward part.** Adding
/// sources re-reads the AUTHORED project from disk, appends paths *relative to
/// the project directory*, writes that back, and only then resolves to
/// absolute for the running tab. Removal has to do the same in reverse or it
/// silently rewrites a portable `.lintcrux` — one whose `rootPath` and sources
/// are relative and survive being committed — into one full of this machine's
/// absolute paths. The file would still work here and break for everyone else
/// on the team, which is the worst way for it to break.
///
/// The confirmation says the file on disk is untouched, because "Remove" next
/// to a filename reads as "delete" to a reasonable person, and the cost of
/// being wrong about that is somebody's RTL.
Future<void> removeSourceFromProject(
  BuildContext context,
  WidgetRef ref, {
  required String absolutePath,
  required String projectName,
}) async {
  final l10n = L10N.of(context);
  final project = ref.read(currentProjectProvider);
  if (project == null) return;

  final confirmed = await confirmCruxDestructiveAction(
    context,
    title: l10n.sourcesRemoveConfirmTitle,
    body: l10n.sourcesRemoveConfirmBody(p.basename(absolutePath)),
    confirmLabel: l10n.sourcesRemoveConfirmAction,
    cancelLabel: l10n.dialogCancel,
  );
  if (!confirmed || !context.mounted) return;

  // The file the tab was opened from; root + name is the fallback derivation
  // for a project loaded without one.
  final projectPath =
      ref.read(currentProjectProvider.notifier).projectFilePath ??
      p.join(project.rootPath, '${project.name}.lintcrux');
  final projectDir = p.dirname(projectPath);
  const service = ProjectFileService();

  final LintProject authored;
  try {
    authored = await service.read(projectPath);
  } on ProjectFileException catch (e) {
    if (!context.mounted) return;
    showCruxErrorSnack(context, e.message);
    return;
  }

  // Match on the RESOLVED path, not the authored string. The panel shows what
  // the running tab holds (absolute), the file stores what the author wrote
  // (usually relative), and comparing those directly removes nothing.
  final remaining = <String>[
    for (final authoredPath in authored.sourceFiles)
      if (p.canonicalize(p.join(projectDir, authoredPath)) !=
          p.canonicalize(absolutePath))
        authoredPath,
  ];
  if (remaining.length == authored.sourceFiles.length) {
    // Nothing matched. Better to say so than to report a success that changed
    // no file and leave the user wondering why the entry is still listed.
    if (!context.mounted) return;
    showCruxErrorSnack(
      context,
      l10n.sourcesRemoveNotFound(p.basename(absolutePath)),
    );
    return;
  }

  try {
    await service.write(projectPath, authored.copyWith(sourceFiles: remaining));
  } on ProjectFileException catch (e) {
    if (!context.mounted) return;
    showCruxErrorSnack(context, e.message);
    return;
  }

  final resolved = resolveProjectPaths(
    authored.copyWith(sourceFiles: remaining),
    projectDir,
  );
  ref
      .read(currentProjectProvider.notifier)
      .load(resolved, projectFilePath: projectPath);
  // Re-run, because the violation table still holds findings from the file
  // that was just removed. Leaving them would show violations for a source
  // the project no longer has.
  unawaited(ref.read(lintRunProvider.notifier).runAll(resolved));

  if (!context.mounted) return;
  showCruxInfoSnack(
    context,
    l10n.sourcesRemoved(p.basename(absolutePath), projectName),
  );
}
