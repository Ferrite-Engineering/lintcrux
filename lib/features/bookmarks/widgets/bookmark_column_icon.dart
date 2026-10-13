// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/bookmarked_violation.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/bookmarks/services/bookmark_dialog_launcher.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/bookmarks/bookmark_freshness.dart';
import 'package:lintcrux/services/bookmarks/violation_bookmark_lookup_provider.dart';
import 'package:lintcrux/services/bookmarks/violation_bookmark_store_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:logging/logging.dart';

/// Per-row bookmark icon rendered in the violation table's bookmark
/// column (see `kBookmarkLeadingCell`).
///
/// Three visual states:
///
/// 1. **Not bookmarked** — outlined [Icons.bookmark_border]. Tap opens
///    the add-bookmark dialog ([showBookmarkDialogFor]) so the user can
///    attach a note and a color tag.
/// 2. **Bookmarked** — filled [Icons.bookmark]. Tap removes the
///    bookmark immediately, which keeps the column-icon ergonomics
///    tight, and shows a snackbar with an Undo action that re-inserts
///    the just-removed bookmark.
/// 3. **Bookmarked + stale** — filled icon dimmed with a small
///    clock-overlay glyph. Triggered when the bookmark's
///    `lastSeenRunId` is non-null *and* differs from the most
///    recent lint run id. Bookmarks that have never re-fired since
///    creation (`lastSeenRunId == null`) are not marked stale —
///    those are "pending first match" instead.
///
/// When [BookmarkedViolation.color] is set, a small color swatch
/// renders beside the icon. The swatch survives stale-state changes.
class BookmarkColumnIcon extends ConsumerWidget {
  /// Creates a [BookmarkColumnIcon] for [violation].
  const BookmarkColumnIcon({required this.violation, super.key});

  /// The row's violation.
  final Violation violation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lookup = ref.watch(violationBookmarkLookupMapProvider);
    final latestRunId = ref.watch(bookmarkFreshnessProvider);
    final fingerprint = computeBookmarkFingerprint(
      violation,
      projectRoot: ref.watch(
        currentProjectProvider.select((p) => p?.rootPath ?? ''),
      ),
    );
    final bookmark = lookup.maybeWhen(
      data: (m) => m[fingerprint],
      orElse: () => null,
    );
    final l10n = L10N.of(context);

    final isBookmarked = bookmark != null;
    final isStale =
        isBookmarked &&
        bookmark.lastSeenRunId != null &&
        latestRunId != null &&
        bookmark.lastSeenRunId != latestRunId;

    final tooltip = isBookmarked
        ? (isStale
              ? '${l10n.bookmarkColumnIconRemoveTooltip} '
                    '(${l10n.bookmarkColumnIconStaleTooltip})'
              : l10n.bookmarkColumnIconRemoveTooltip)
        : l10n.bookmarkColumnIconAddTooltip;

    final scheme = Theme.of(context).colorScheme;
    final iconColor = !isBookmarked
        ? scheme.onSurfaceVariant
        : isStale
        ? scheme.primary.withAlpha(110)
        : scheme.primary;

    return Tooltip(
      message: tooltip,
      child: InkResponse(
        radius: 16,
        onTap: () => _onTap(context, ref, bookmark),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (bookmark != null && bookmark.color != null)
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: _ColorSwatch(hex: bookmark.color!),
                ),
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Icon(
                    isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                    size: 18,
                    color: iconColor,
                    key: ValueKey(
                      'bookmarkColumnIcon-'
                      '${isBookmarked ? 'on' : 'off'}'
                      '${isStale ? '-stale' : ''}',
                    ),
                  ),
                  if (isStale)
                    Icon(
                      Icons.schedule,
                      size: 10,
                      color: scheme.onSurfaceVariant,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onTap(
    BuildContext context,
    WidgetRef ref,
    BookmarkedViolation? bookmark,
  ) async {
    if (bookmark == null) {
      // Create path: the same dialog the Toggle Bookmark action opens.
      await showBookmarkDialogFor(
        context,
        ProviderScope.containerOf(context, listen: false),
        violation,
      );
      return;
    }
    // Remove path — remove from the store, then surface a snackbar with
    // Undo that re-inserts the just-removed bookmark.
    //
    // Undo holds the tab's container, not the store. The per-tab store is
    // rebuilt whenever the tab's project changes (a severity-override edit
    // is enough), and the snackbar outlives that. The old store still holds
    // its snapshot from before the rebuild, and every write replaces the
    // whole file with the writer's snapshot, so an Undo through it would
    // erase every bookmark made since. Nor can it hold `ref`: the row may be
    // gone by the time Undo is pressed.
    final container = ProviderScope.containerOf(context, listen: false);
    final removed = bookmark;
    await ref.read(violationBookmarkStoreProvider).remove(removed.id);
    if (!context.mounted) return;
    final l10n = L10N.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.bookmarkRemovedSnackbar),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: l10n.bookmarkRemovedUndoLabel,
          onPressed: () => _undoRemove(container, removed),
        ),
      ),
    );
  }

  /// Re-adds [removed] through the store [container] holds NOW. The store's
  /// `addOrUpdate` is keyed by `id`, so the undo restores the exact prior
  /// state including note / color / createdAt.
  static void _undoRemove(
    ProviderContainer container,
    BookmarkedViolation removed,
  ) {
    unawaited(
      Future<void>.sync(
        () =>
            container.read(violationBookmarkStoreProvider).addOrUpdate(removed),
      ).catchError((Object error, StackTrace st) {
        // The tab closed under the snackbar (its container is disposed), the
        // store refuses writes (an unreadable bookmark file), or the row was
        // bookmarked again since the removal.
        Logger('lintcrux.bookmarks').warning(
          'Bookmark ${removed.id} was not restored',
          error,
          st,
        );
      }),
    );
  }
}

/// Small 12 dp color swatch rendered beside the bookmark icon when the
/// bookmark has a color tag set. Tolerates malformed hex by falling
/// back to a neutral disabled color.
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.hex});

  final String hex;

  @override
  Widget build(BuildContext context) {
    final color = _parseHex(hex) ?? Theme.of(context).disabledColor;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
    );
  }

  Color? _parseHex(String input) {
    final s = input.startsWith('#') ? input.substring(1) : input;
    if (s.length != 6 && s.length != 8) return null;
    final value = int.tryParse(s, radix: 16);
    if (value == null) return null;
    return Color(s.length == 6 ? 0xFF000000 | value : value);
  }
}
