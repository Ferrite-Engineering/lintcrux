// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// One row of the welcome screen's Recent projects list.
///
/// Tapping the row opens [path]; the trailing button removes it from the
/// list. A row whose project file is gone ([exists] false) is greyed and
/// says so; it stays tappable, so opening it reports why it failed and drops
/// it, and its remove button works like any other.
class RecentProjectTile extends StatelessWidget {
  /// Creates a row for [path].
  const RecentProjectTile({
    required this.path,
    required this.exists,
    required this.onOpen,
    required this.onRemove,
    super.key,
  });

  /// The project file's absolute path.
  final String path;

  /// Whether the project file is still on disk.
  final bool exists;

  /// Opens the project.
  final VoidCallback onOpen;

  /// Removes the entry from Recent projects.
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        exists ? Icons.folder_outlined : Icons.folder_off_outlined,
        color: exists ? null : muted,
      ),
      title: Text(
        path,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: exists ? null : TextStyle(color: muted),
      ),
      subtitle: exists
          ? null
          : Text(
              l10n.emptyCanvasRecentProjectMissing,
              style: TextStyle(color: muted),
            ),
      onTap: onOpen,
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 16),
        tooltip: l10n.emptyCanvasRemoveRecentProject,
        color: muted,
        visualDensity: VisualDensity.compact,
        onPressed: onRemove,
      ),
    );
  }
}
