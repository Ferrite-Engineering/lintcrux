// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/features/bookmarks/providers/bookmark_openers.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/bookmarks/bookmarked_violations_count_provider.dart';

/// Chip showing the live bookmark count, with a click target that opens
/// the bookmark management panel.
///
/// Rendered by `ViolationTable` in its top-action row whenever the tab
/// has a project open. The chip shows zero gracefully: it stays visible
/// so the user has a discoverable click target to the bookmark panel
/// even before they have created any bookmarks. The tooltip pluralizes
/// "{count} bookmarks" via the ICU `plural` selector.
class BookmarkCountBadge extends ConsumerWidget {
  /// Creates a [BookmarkCountBadge].
  const BookmarkCountBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countAsync = ref.watch(bookmarkedViolationsCountProvider);
    final count = countAsync.maybeWhen(data: (n) => n, orElse: () => 0);
    final l10n = L10N.of(context);
    final scheme = Theme.of(context).colorScheme;
    final message = l10n.bookmarkCountBadgeTooltip(count);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      // One button, one name: the count is spoken as the tooltip's sentence
      // (`semanticsLabel`) and the tooltip itself stays out of semantics, so a
      // screen reader does not hear the bare count and the tooltip as two
      // names for one stop.
      child: Tooltip(
        message: message,
        excludeFromSemantics: true,
        child: Semantics(
          button: true,
          child: InkResponse(
            radius: 18,
            onTap: () async {
              final opener = ref.read(bookmarkPanelOpenerProvider);
              if (opener == null) return;
              await Future.sync(() => opener(context));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bookmark,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    semanticsLabel: message,
                    key: const ValueKey('bookmarkCountBadgeText'),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
