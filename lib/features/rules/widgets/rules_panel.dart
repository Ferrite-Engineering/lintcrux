// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/rule.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/rules/rule_database_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Browses the rule database.
///
/// Without this panel the database is only reachable *reactively*: the
/// Inspector looks up the rule of whichever violation you have selected, so you
/// can read about a rule you have already tripped over and no other way. On a
/// 246-rule engine that is a lucky encounter, not a catalog.
///
/// This is the proactive half — see what an engine can emit before you hit it,
/// look up a rule someone cited in review, filter by tag. Search matches the
/// rule id and its tags, because those are the two things a user arrives
/// holding: a name from a log, or a category they are auditing for.
class RulesPanel extends ConsumerStatefulWidget {
  /// Creates the panel.
  const RulesPanel({super.key});

  @override
  ConsumerState<RulesPanel> createState() => _RulesPanelState();
}

class _RulesPanelState extends ConsumerState<RulesPanel> {
  final TextEditingController _search = TextEditingController();
  String? _engineFilter;

  // The rule list is one Tab stop, not two per rule.
  //
  // A database holds several hundred rules, and each row is a button with a
  // documentation link beside it, so a keyboard or screen-reader user
  // tabbing from the filters to the violations table beside this panel
  // passed through well over a thousand stops. Only the row that last held
  // focus (and its link) is in the Tab order; Up and Down move between rows.

  /// Focus nodes for each rule's row and documentation link, keyed by rule
  /// id. Created as rows build and kept for the panel's lifetime: the rule
  /// database is fixed-size, and a node disposed while its virtualized row
  /// is still mounted would be used after disposal.
  final Map<String, FocusNode> _rowNodes = <String, FocusNode>{};
  final Map<String, FocusNode> _linkNodes = <String, FocusNode>{};

  /// Rule ids in list order, as last built.
  List<String> _order = const <String>[];

  /// The rule whose row holds the list's single Tab stop.
  String? _tabStop;

  @override
  void dispose() {
    _search.dispose();
    for (final node in [..._rowNodes.values, ..._linkNodes.values]) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _rowNode(String id) => _rowNodes.putIfAbsent(id, () {
    final node = FocusNode(
      debugLabel: 'Rule row',
      skipTraversal: id != _tabStop,
    );
    node.addListener(() {
      // Deferred: focus listeners run while the focus manager is still
      // iterating its dirty nodes, and changing `skipTraversal` marks nodes
      // dirty, which throws a concurrent modification there.
      if (node.hasPrimaryFocus) {
        scheduleMicrotask(() {
          if (mounted && node.hasPrimaryFocus) _moveTabStop(id);
        });
      }
    });
    return node;
  });

  FocusNode _linkNode(String id) => _linkNodes.putIfAbsent(
    id,
    () => FocusNode(
      debugLabel: 'Rule documentation link',
      skipTraversal: id != _tabStop,
    ),
  );

  void _moveTabStop(String? id) {
    if (_tabStop == id) return;
    final previous = _tabStop;
    if (previous != null) {
      _rowNodes[previous]?.skipTraversal = true;
      _linkNodes[previous]?.skipTraversal = true;
    }
    _tabStop = id;
    if (id != null) {
      _rowNodes[id]?.skipTraversal = false;
      _linkNodes[id]?.skipTraversal = false;
    }
  }

  /// Keeps the Tab stop on a rule that is still listed after the search or
  /// engine filter changed.
  void _syncTabStop(List<Rule> rules) {
    _order = <String>[for (final rule in rules) rule.id];
    final stop = _tabStop;
    if (stop != null && _order.contains(stop)) return;
    _moveTabStop(_order.isEmpty ? null : _order.first);
  }

  /// Focuses the row [delta] rows from the Tab stop. The neighbour of a
  /// focused, on-screen row is always inside the list's cache extent, so it
  /// has been built and its node is attached.
  void _focusRow(int delta) {
    if (_order.isEmpty) return;
    final stop = _tabStop;
    final from = stop == null ? 0 : _order.indexOf(stop);
    final index = (from + delta).clamp(0, _order.length - 1);
    final rowContext = (_rowNode(_order[index])..requestFocus()).context;
    if (rowContext == null) return;
    Scrollable.ensureVisible(
      rowContext,
      alignmentPolicy: delta > 0
          ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
          : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final dbAsync = ref.watch(ruleDatabaseProvider);
    return dbAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => CruxPanelEmptyState(message: l10n.rulesPanelLoadFailed),
      data: (db) {
        final query = _search.text.trim().toLowerCase();
        final engines = db.engineIds;
        final rules = <Rule>[
          for (final engineId in engines)
            if (_engineFilter == null || _engineFilter == engineId)
              ...db.rulesFor(engineId),
        ].where((r) => _matches(r, query)).toList(growable: false);
        _syncTabStop(rules);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Filters(
              controller: _search,
              engines: engines,
              selected: _engineFilter,
              onEngine: (id) => setState(() => _engineFilter = id),
              onQuery: () => setState(() {}),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                l10n.rulesPanelCount(rules.length),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: rules.isEmpty
                  ? CruxPanelEmptyState(message: l10n.rulesPanelEmpty)
                  : CallbackShortcuts(
                      bindings: <ShortcutActivator, VoidCallback>{
                        const SingleActivator(
                          LogicalKeyboardKey.arrowDown,
                        ): () =>
                            _focusRow(1),
                        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                            _focusRow(-1),
                      },
                      child: ListView.builder(
                        itemCount: rules.length,
                        itemBuilder: (_, i) {
                          final rule = rules[i];
                          return _RuleRow(
                            rule: rule,
                            focusNode: _rowNode(rule.id),
                            linkFocusNode: rule.helpUri == null
                                ? null
                                : _linkNode(rule.id),
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  /// Substring match over id and tags.
  ///
  /// Deliberately not fuzzy. A user searching `UNUSED` wants the rules whose
  /// name contains it, and a fuzzy matcher that also surfaces `UNDRIVEN`
  /// makes a precise query worse to serve an imprecise one nobody made.
  static bool _matches(Rule rule, String query) {
    if (query.isEmpty) return true;
    if (rule.id.toLowerCase().contains(query)) return true;
    return rule.tags.any((t) => t.toLowerCase().contains(query));
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.controller,
    required this.engines,
    required this.selected,
    required this.onEngine,
    required this.onQuery,
  });

  final TextEditingController controller;
  final List<String> engines;
  final String? selected;
  final ValueChanged<String?> onEngine;
  final VoidCallback onQuery;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            onChanged: (_) => onQuery(),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: l10n.rulesPanelSearchHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ChoiceChip(
                  label: Text(l10n.rulesPanelAllEngines),
                  selected: selected == null,
                  onSelected: (_) => onEngine(null),
                ),
                for (final id in engines) ...[
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: Text(id),
                    selected: selected == id,
                    onSelected: (_) => onEngine(id),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RuleRow extends ConsumerWidget {
  const _RuleRow({
    required this.rule,
    required this.focusNode,
    required this.linkFocusNode,
  });

  final Rule rule;

  /// The row's focus node, owned by the panel, which moves the list's Tab
  /// stop between rows.
  final FocusNode focusNode;

  /// The documentation link's focus node, or null when the rule has none.
  final FocusNode? linkFocusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final scheme = Theme.of(context).colorScheme;
    final help = rule.helpUri;
    return ListTile(
      dense: true,
      focusNode: focusNode,
      title: Text(
        rule.id,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: rule.tags.isEmpty
          ? null
          : Text(
              rule.tags.join(' · '),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
      leading: _SeverityDot(severity: rule.defaultSeverity),
      // Tapping a rule filters the violations table to it. The browser
      // answers "what can this engine report"; the obvious next question is
      // "and did it, here", which is one tap away rather than a retype into
      // the filter field.
      //
      // The table's filter is a substring over ruleId + message, so passing
      // the namespaced id scopes it to exactly this rule.
      onTap: () => ref
          .read(violationTableStateProvider.notifier)
          .setRuleSubstring(rule.id),
      trailing: help == null
          ? null
          : IconButton(
              focusNode: linkFocusNode,
              icon: const Icon(Icons.open_in_new, size: 16),
              tooltip: l10n.rulesPanelLearnMore,
              onPressed: () => launchUrl(help),
            ),
    );
  }
}

class _SeverityDot extends StatelessWidget {
  const _SeverityDot({required this.severity});

  final Severity severity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (severity) {
      Severity.fatal || Severity.error => scheme.error,
      Severity.warning => Colors.orange,
      Severity.note => scheme.primary,
      Severity.none => scheme.onSurfaceVariant,
    };
    return Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
