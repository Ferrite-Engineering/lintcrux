// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/bookmarked_violation.dart';
import 'package:lintcrux/features/bookmarks/widgets/bookmark_dialog.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/workspace/services/active_tab_scope.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/bookmarks/bookmark_freshness.dart';
import 'package:lintcrux/services/bookmarks/violation_bookmark_lookup_provider.dart';
import 'package:lintcrux/services/bookmarks/violation_bookmark_store_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';

/// Bookmark management panel — modal full-screen dialog rendering
/// every [BookmarkedViolation] grouped by file path, with filter chips
/// (All / Active / Stale), a substring search, and per-row actions
/// (Jump to violation, Edit note, Remove bookmark).
///
/// Mounted through `bookmarkPanelOpenerProvider` (the Show Bookmarked
/// Violations action and the bookmark count badge).
class BookmarkPanel extends ConsumerStatefulWidget {
  /// Creates the bookmark management panel.
  const BookmarkPanel({super.key});

  /// Convenience launcher. Mounts the panel as a full-screen dialog
  /// rooted at [context].
  ///
  /// Guarded: reached from `bookmarkPanelOpenerProvider` (keyboard
  /// shortcut / command dispatch), so a fast double-fire must not stack two
  /// copies.
  ///
  /// Carries a substring-search field holding in-progress query state, so
  /// the barrier stays non-dismissible.
  static Future<void> showAsDialog(BuildContext context) {
    return ModalGuard.run(
      'bookmarkPanel',
      () => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => wrapInActiveTabScope(
          context,
          const Dialog.fullscreen(
            child: EscapeDismissible(child: BookmarkPanel()),
          ),
        ),
      ),
    );
  }

  @override
  ConsumerState<BookmarkPanel> createState() => _BookmarkPanelState();
}

enum _BookmarkFilterMode { all, active, stale }

class _BookmarkPanelState extends ConsumerState<BookmarkPanel> {
  _BookmarkFilterMode _filter = _BookmarkFilterMode.all;
  String _search = '';

  bool _isStale(BookmarkedViolation bm, String? latestRunId) {
    return bm.lastSeenRunId != null &&
        latestRunId != null &&
        bm.lastSeenRunId != latestRunId;
  }

  List<BookmarkedViolation> _apply(
    List<BookmarkedViolation> all,
    String? latestRunId,
  ) {
    final byFilter = switch (_filter) {
      _BookmarkFilterMode.all => all,
      _BookmarkFilterMode.active =>
        all
            .where(
              (bm) => !_isStale(bm, latestRunId),
            )
            .toList(),
      _BookmarkFilterMode.stale =>
        all
            .where(
              (bm) => _isStale(bm, latestRunId),
            )
            .toList(),
    };
    if (_search.isEmpty) return byFilter;
    final q = _search.toLowerCase();
    return byFilter.where((bm) {
      return bm.ruleId.toLowerCase().contains(q) ||
          bm.filePath.toLowerCase().contains(q) ||
          bm.snippet.toLowerCase().contains(q) ||
          (bm.note?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Map<String, List<BookmarkedViolation>> _groupByFile(
    List<BookmarkedViolation> list,
  ) {
    final out = <String, List<BookmarkedViolation>>{};
    for (final bm in list) {
      out.putIfAbsent(bm.filePath, () => []).add(bm);
    }
    // Sort entries within each file by line then created.
    for (final entries in out.values) {
      entries.sort((a, b) {
        final byLine = a.lineNumber.compareTo(b.lineNumber);
        if (byLine != 0) return byLine;
        return a.createdAt.compareTo(b.createdAt);
      });
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final lookup = ref.watch(violationBookmarkLookupMapProvider);
    final latestRunId = ref.watch(bookmarkFreshnessProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(l10n.bookmarkPanelTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
      body: lookup.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (map) {
          final all = map.values.toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          final filtered = _apply(all, latestRunId);
          final grouped = _groupByFile(filtered);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ChoiceChip(
                      key: const ValueKey('bookmarkPanelFilterAll'),
                      label: Text(l10n.bookmarkPanelFilterAll),
                      selected: _filter == _BookmarkFilterMode.all,
                      onSelected: (_) =>
                          setState(() => _filter = _BookmarkFilterMode.all),
                    ),
                    ChoiceChip(
                      key: const ValueKey('bookmarkPanelFilterActive'),
                      label: Text(l10n.bookmarkPanelFilterActive),
                      selected: _filter == _BookmarkFilterMode.active,
                      onSelected: (_) =>
                          setState(() => _filter = _BookmarkFilterMode.active),
                    ),
                    ChoiceChip(
                      key: const ValueKey('bookmarkPanelFilterStale'),
                      label: Text(l10n.bookmarkPanelFilterStale),
                      selected: _filter == _BookmarkFilterMode.stale,
                      onSelected: (_) =>
                          setState(() => _filter = _BookmarkFilterMode.stale),
                    ),
                    SizedBox(
                      width: 280,
                      child: TextField(
                        key: const ValueKey('bookmarkPanelSearch'),
                        decoration: InputDecoration(
                          hintText: l10n.bookmarkPanelSearchHint,
                          prefixIcon: const Icon(Icons.search, size: 18),
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => _search = v),
                      ),
                    ),
                  ],
                ),
              ),
              if (all.isEmpty)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        l10n.bookmarkPanelEmptyState,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              else if (filtered.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      l10n.bookmarkPanelEmptyFiltered,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    children: [
                      for (final entry in grouped.entries) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          color: scheme.surfaceContainerHighest,
                          child: Text(
                            entry.key,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                        for (final bm in entry.value)
                          _BookmarkRow(
                            bookmark: bm,
                            isStale: _isStale(bm, latestRunId),
                          ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _BookmarkRow extends ConsumerWidget {
  const _BookmarkRow({
    required this.bookmark,
    required this.isStale,
  });

  final BookmarkedViolation bookmark;
  final bool isStale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      key: ValueKey('bookmarkPanelRow-${bookmark.id}'),
      dense: true,
      leading: Icon(
        Icons.bookmark,
        color: isStale ? scheme.primary.withAlpha(120) : scheme.primary,
        size: 22,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              '${bookmark.ruleId} : line ${bookmark.lineNumber}',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (isStale)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Text(
                l10n.bookmarkPanelRowStaleBadge,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            bookmark.snippet,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (bookmark.note != null && bookmark.note!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _firstLine(bookmark.note!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        key: ValueKey('bookmarkPanelRowMenu-${bookmark.id}'),
        icon: const Icon(Icons.more_vert, size: 18),
        onSelected: (action) => _onAction(context, ref, l10n, action),
        itemBuilder: (_) => [
          PopupMenuItem<String>(
            value: 'jump',
            child: Text(l10n.bookmarkPanelRowJumpAction),
          ),
          PopupMenuItem<String>(
            value: 'edit',
            child: Text(l10n.bookmarkPanelRowEditAction),
          ),
          PopupMenuItem<String>(
            value: 'remove',
            child: Text(l10n.bookmarkPanelRowRemoveAction),
          ),
        ],
      ),
    );
  }

  String _firstLine(String s) {
    final i = s.indexOf('\n');
    return (i < 0 ? s : s.substring(0, i)).trim();
  }

  // Not `async`: each case hands back its own future. The cases are
  // exclusive, and an `await` on one would read as a use of `ref` after it.
  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    L10N l10n,
    String action,
  ) => switch (action) {
    'jump' => Future<void>.sync(() => _jumpToViolation(context, ref)),
    'edit' => _openEditDialog(context, ref),
    'remove' => _confirmAndRemove(context, ref, l10n),
    _ => Future<void>.value(),
  };

  void _jumpToViolation(BuildContext context, WidgetRef ref) {
    // Find the matching live violation in the visible set and select
    // it; the table will scroll it into view via the table's own
    // selection-update plumbing. If no live match (the bookmark is
    // stale), close the panel anyway and show nothing — the snackbar
    // story for stale-jump can grow later.
    final visible = ref.read(visibleViolationsProvider);
    final fingerprint = bookmark.fingerprint;
    final projectRoot = ref.read(currentProjectProvider)?.rootPath ?? '';
    for (final v in visible) {
      final vfp = computeBookmarkFingerprint(v, projectRoot: projectRoot);
      if (vfp == fingerprint) {
        ref.read(selectedViolationProvider.notifier).select(v);
        break;
      }
    }
    Navigator.of(context).pop();
  }

  Future<void> _openEditDialog(BuildContext context, WidgetRef ref) async {
    // Shared key with `showBookmarkDialogFor`: this row's "Edit" entry,
    // the Toggle Bookmark action and the column icon all reach the same
    // `BookmarkDialog`, so a fast double-fire from any of them must not
    // stack two dialogs over the same bookmark.
    await ModalGuard.run('bookmarkDialog', () async {
      // The edit dialog writes the per-tab bookmark store; showDialog
      // mounts on the root navigator, so re-wrap in the active tab scope
      // (the panel itself is already wrapped, but that wrap does not
      // extend to routes pushed from inside it).
      await showDialog<void>(
        context: context,
        // A note + color-tag editor holding in-progress user input:
        // closing must be a deliberate act, never a stray scrim click.
        barrierDismissible: false,
        builder: (_) => wrapInActiveTabScope(
          context,
          BookmarkDialog(existing: bookmark),
        ),
      );
    });
  }

  Future<void> _confirmAndRemove(
    BuildContext context,
    WidgetRef ref,
    L10N l10n,
  ) async {
    // Read before the dialog: the store outlives this row, which the
    // confirmation may outlast (the panel closed, the list re-sorted).
    final store = ref.read(violationBookmarkStoreProvider);
    final confirmed = await confirmCruxDestructiveAction(
      context,
      title: l10n.bookmarkPanelRemoveConfirmTitle,
      body: l10n.bookmarkPanelRemoveConfirmBody,
      confirmLabel: l10n.bookmarkPanelRemoveConfirmYes,
      cancelLabel: l10n.bookmarkPanelRemoveConfirmNo,
    );
    if (!confirmed) return;
    await store.remove(bookmark.id);
  }
}
