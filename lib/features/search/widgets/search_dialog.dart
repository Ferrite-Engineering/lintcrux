// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/core/help_urls.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/features/workspace/services/active_tab_scope.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/search/violation_search.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';

/// Convenience launcher — call from a `ShortcutAction` handler or a
/// command-palette entry.
///
/// On the desktop the dialog reads the *active tab's*
/// `violationStoreProvider` / `selectedViolationProvider`, so it is wrapped
/// in [wrapInActiveTabScope]: a bare `showDialog` mounts the dialog on the
/// root Navigator, whose `ProviderScope` is the root container (empty
/// violation store) rather than the active tab's. [context] must carry
/// `WorkspaceRoot` in its ancestor chain — pass the activating context
/// (the routerDelegate navigator's context), not the dialog builder's.
///
/// Pass [activeTab] `false` where the violations on screen live in the root
/// scope instead: the browser viewer, which has no workspace and no tabs, and
/// whose SARIF loader fills the root container's store. The dialog then
/// searches and selects in that scope and never touches the workspace.
Future<void> showViolationSearchDialog(
  BuildContext context, {
  bool activeTab = true,
}) {
  // Re-entrancy guard: Cmd/Ctrl+F auto-repeat or a double-tap on the menu /
  // palette entry must not stack a second search dialog. Guarded inside the
  // launcher so every caller is covered.
  return ModalGuard.run(
    'search',
    () => showDialog<void>(
      context: context,
      builder: (_) => activeTab
          ? wrapInActiveTabScope(context, const SearchDialog())
          : const SearchDialog(),
    ),
  );
}

/// Modal search overlay (Cmd/Ctrl+F), hosted on the suite-standard
/// [CruxSearchDialog] shell (query field, debounce, ↑/↓/Enter navigation,
/// empty state).
///
/// LintCrux supplies the three search-mode chips via the shell's header
/// seam and searches rule id + message of the active project's violation
/// store; activating a result selects it (which scrolls the table to the
/// row via the existing `selectedViolationProvider` plumbing).
class SearchDialog extends ConsumerStatefulWidget {
  /// Creates a [SearchDialog].
  const SearchDialog({super.key});

  @override
  ConsumerState<SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends ConsumerState<SearchDialog> {
  static const ViolationSearch _service = ViolationSearch();

  SearchMode _mode = SearchMode.substring;

  List<SearchMatch> _search(String query) => _service.search(
    haystack: ref.read(violationStoreProvider).all,
    query: query,
    mode: _mode,
  );

  Widget _modeChips(BuildContext context, VoidCallback refresh) {
    final l10n = L10N.of(context);
    void select(SearchMode mode) {
      setState(() => _mode = mode);
      refresh();
    }

    return Row(
      children: <Widget>[
        _ModeChip(
          label: l10n.searchModeSubstring,
          mode: SearchMode.substring,
          selected: _mode == SearchMode.substring,
          onSelected: select,
        ),
        const SizedBox(width: 8),
        _ModeChip(
          label: l10n.searchModeGlob,
          mode: SearchMode.glob,
          selected: _mode == SearchMode.glob,
          onSelected: select,
        ),
        const SizedBox(width: 8),
        _ModeChip(
          label: l10n.searchModeRegex,
          mode: SearchMode.regex,
          selected: _mode == SearchMode.regex,
          onSelected: select,
        ),
        const Spacer(),
        // Contextual docs: the violations guide (filtering, search modes,
        // keyboard navigation).
        CruxHelpLink(
          url: HelpUrls.violationSearch,
          tooltip: l10n.helpLinkLearnMore,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return CruxSearchDialog<SearchMatch>(
      title: l10n.searchDialogTitle,
      hintText: l10n.searchDialogHint,
      emptyLabel: l10n.searchNoResults,
      fieldKey: const ValueKey('searchDialogInput'),
      search: _search,
      headerBuilder: _modeChips,
      // `search.used` fires when the user actually picks a result, not on
      // every keystroke: `CruxSearchDialog` re-runs `_search` as the query
      // changes, and counting there would report a dozen searches for one.
      // Only the mode is sent — the query is free text the user typed, and
      // free text is never collected.
      onActivateResult: (match) {
        ref
            .read(telemetryServiceProvider)
            .record(
              TelemetryEvent(
                'search.used',
                properties: <String, Object?>{
                  'mode': telemetryEnumToken(_mode),
                },
              ),
            );
        ref.read(selectedViolationProvider.notifier).select(match.violation);
      },
      rowBuilder:
          (rowContext, match, {required highlighted, required onActivate}) {
            final v = match.violation;
            return CruxSearchResultTile(
              title: v.ruleId,
              subtitle: v.message,
              trailingChipLabel: '${v.location.file}:${v.location.line}',
              highlighted: highlighted,
              onTap: onActivate,
            );
          },
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.mode,
    required this.selected,
    required this.onSelected,
  });
  final String label;
  final SearchMode mode;
  final bool selected;
  final ValueChanged<SearchMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      key: ValueKey('searchModeChip-${mode.name}'),
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(mode),
    );
  }
}
