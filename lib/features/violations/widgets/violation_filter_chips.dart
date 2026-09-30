// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_async/crux_async.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/features/violations/providers/present_engine_ids_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_filter_focus_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/violations/widgets/severity_chip.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/telemetry/telemetry_event_catalog.dart';

/// Strip of filter chips + text-field inputs rendered above the
/// violation table.
class ViolationFilterChips extends ConsumerStatefulWidget {
  /// Creates a [ViolationFilterChips].
  const ViolationFilterChips({super.key});

  @override
  ConsumerState<ViolationFilterChips> createState() =>
      _ViolationFilterChipsState();
}

class _ViolationFilterChipsState extends ConsumerState<ViolationFilterChips> {
  late final TextEditingController _ruleCtrl;
  late final TextEditingController _fileCtrl;

  /// Records `filter.used` — "which triage filters earn their place".
  ///
  /// Deliberately here, at the widget, and **not** on `ViolationTableNotifier`'s
  /// setters. Session restore (`OpenProjectInWorkspace.openSession`) and tab
  /// hydration (`ProjectTabContent`) replay a saved filter state through those
  /// same setters, so a counter on the notifier would report a filter every
  /// time a tab was rehydrated and the answer would be "everyone uses every
  /// filter constantly". Only a user gesture reaches this widget.
  ///
  /// The debounced text fields report on the debounced call rather than per
  /// keystroke, for the same reason the filter itself is debounced: "the user
  /// filtered by rule" happened once.
  void _recordFilterUsed(LintcruxFilterKind kind) {
    ref
        .read(telemetryServiceProvider)
        .record(
          TelemetryEvent(
            'filter.used',
            properties: <String, Object?>{'kind': telemetryEnumToken(kind)},
          ),
        );
  }

  // Coalesce per-keystroke filter updates: applying the filter runs a full
  // filter + sort + copy over the store (and, in Only-new view mode, a
  // fingerprint lookup per row — memoized per violation, so only a run's
  // first derive hashes), so we defer it until typing settles (the
  // Debouncer's default 200 ms trailing delay) rather than firing on every
  // keystroke.
  final Debouncer _ruleDebouncer = Debouncer();
  final Debouncer _fileDebouncer = Debouncer();

  @override
  void initState() {
    super.initState();
    final initial = ref.read(violationTableStateProvider);
    _ruleCtrl = TextEditingController(text: initial.ruleSubstring);
    _fileCtrl = TextEditingController(text: initial.fileGlob);
  }

  @override
  void dispose() {
    _ruleDebouncer.dispose();
    _fileDebouncer.dispose();
    _ruleCtrl.dispose();
    _fileCtrl.dispose();
    super.dispose();
  }

  /// Syncs the controller when the notifier value changes from outside the
  /// TextField (workspace restore, preset application). An external change
  /// cancels any in-flight debounced keystroke so the external value wins.
  void _syncController(
    TextEditingController c,
    String next,
    Debouncer debouncer,
  ) {
    if (c.text == next) return;
    debouncer.cancel();
    c.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final tableState = ref.watch(violationTableStateProvider);
    final notifier = ref.read(violationTableStateProvider.notifier);
    // Per-engine chips are derived from the engine ids present in the
    // loaded report (see `presentEngineIdsProvider`), NOT the engine
    // registry: the registry eagerly builds run-time engine runners that
    // call `dart:io Platform` and crash the read-only web viewer.
    final engineIds = ref.watch(presentEngineIdsProvider);
    // Keep the controllers in sync when the notifier value changes
    // from outside the TextField (e.g. workspace restore loading the
    // payload's `ruleSubstring` / `fileGlob`, preset application).
    _syncController(_ruleCtrl, tableState.ruleSubstring, _ruleDebouncer);
    _syncController(_fileCtrl, tableState.fileGlob, _fileDebouncer);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final s in Severity.values)
            FilterChip(
              key: ValueKey('violationFilterChip-severity-${s.name}'),
              // The icon's own semantic label is the same word as the chip
              // label, so without the exclusion the chip was announced
              // "Warning Warning".
              avatar: ExcludeSemantics(child: SeverityIcon(severity: s)),
              label: Text(severityLabel(l10n, s)),
              selected: tableState.severities.contains(s),
              onSelected: (_) {
                notifier.toggleSeverity(s);
                _recordFilterUsed(LintcruxFilterKind.severity);
              },
            ),
          for (final engineId in engineIds)
            FilterChip(
              key: ValueKey('violationFilterChip-engine-$engineId'),
              label: Text(engineId),
              selected: tableState.engineIds.contains(engineId),
              onSelected: (_) {
                notifier.toggleEngine(engineId);
                _recordFilterUsed(LintcruxFilterKind.engine);
              },
            ),
          SizedBox(
            width: 240,
            child: TextField(
              key: const ValueKey('violationFilterRuleField'),
              controller: _ruleCtrl,
              focusNode: ref.watch(violationFilterRuleFocusProvider),
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.violationFilterRuleHint,
              ),
              onChanged: (v) => _ruleDebouncer.run(() {
                notifier.setRuleSubstring(v);
                _recordFilterUsed(LintcruxFilterKind.rule);
              }),
            ),
          ),
          SizedBox(
            width: 240,
            child: TextField(
              key: const ValueKey('violationFilterFileField'),
              controller: _fileCtrl,
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.violationFilterFileHint,
              ),
              onChanged: (v) => _fileDebouncer.run(() {
                notifier.setFileGlob(v);
                _recordFilterUsed(LintcruxFilterKind.file);
              }),
            ),
          ),
        ],
      ),
    );
  }
}
